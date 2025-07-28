# frozen_string_literal: true

module Calendar
  class GoogleService < BaseService
    require 'google/apis/calendar_v3'
    require 'googleauth'
    
    def initialize(calendar_connection)
      super(calendar_connection)
      @calendar_service = Google::Apis::CalendarV3::CalendarService.new
      setup_authorization
    end
    
    def create_event(booking)
      return nil unless validate_booking(booking) && validate_connection
      
      with_error_handling do
        event_data = format_booking_for_calendar(booking)
        google_event = build_google_event(event_data)
        
        created_event = @calendar_service.insert_event('primary', google_event)
        
        if created_event&.id
          # Create mapping record
          mapping = CalendarEventMapping.create!(
            booking: booking,
            calendar_connection: calendar_connection,
            external_event_id: created_event.id,
            external_calendar_id: 'primary',
            status: :synced,
            last_synced_at: Time.current
          )
          
          # Update booking calendar status
          booking.update!(
            calendar_event_status: :synced,
            calendar_event_id: created_event.id
          )
          
          log_sync_attempt(mapping, :event_create, :success, "Event created successfully")
          
          {
            success: true,
            external_event_id: created_event.id,
            mapping: mapping
          }
        else
          add_error(:creation_failed, "Failed to create Google Calendar event")
          nil
        end
      end
    end
    
    def update_event(booking, external_event_id)
      return nil unless validate_booking(booking) && validate_connection
      
      mapping = find_event_mapping(booking, external_event_id)
      return nil unless mapping
      
      with_error_handling do
        event_data = format_booking_for_calendar(booking)
        google_event = build_google_event(event_data)
        
        updated_event = @calendar_service.update_event(
          'primary',
          external_event_id,
          google_event
        )
        
        if updated_event&.id
          mapping.mark_synced!(external_event_id)
          booking.update!(calendar_event_status: :synced)
          
          log_sync_attempt(mapping, :event_update, :success, "Event updated successfully")
          
          {
            success: true,
            external_event_id: updated_event.id,
            mapping: mapping
          }
        else
          add_error(:update_failed, "Failed to update Google Calendar event")
          mapping.mark_failed!("Update failed")
          nil
        end
      end
    end
    
    def delete_event(external_event_id)
      return nil unless validate_connection
      
      with_error_handling do
        @calendar_service.delete_event('primary', external_event_id)
        
        # Update any associated mappings
        mappings = calendar_connection.calendar_event_mappings
                                    .where(external_event_id: external_event_id)
        
        mappings.each do |mapping|
          mapping.mark_deleted!
          mapping.booking&.update(calendar_event_status: :not_synced)
          log_sync_attempt(mapping, :event_delete, :success, "Event deleted successfully")
        end
        
        { success: true }
      end
    end
    
    def import_events(start_date, end_date)
      return nil unless validate_connection
      
      with_error_handling do
        events = fetch_google_events(start_date, end_date)
        import_result = ExternalCalendarEvent.import_for_connection(
          calendar_connection,
          events
        )
        
        calendar_connection.mark_synced!
        
        {
          success: true,
          imported_count: import_result[:imported_count],
          errors: import_result[:errors]
        }
      end
    end
    
    def refresh_access_token
      oauth_handler = OauthHandler.new
      result = oauth_handler.refresh_token(calendar_connection)
      
      if result
        setup_authorization
        true
      else
        oauth_handler.errors.each do |error|
          add_error(error.attribute, error.message)
        end
        false
      end
    end
    
    private
    
    def setup_authorization
      return unless calendar_connection.access_token
      
      client_id = Rails.application.credentials.dig(:google_calendar, :client_id)
      client_secret = Rails.application.credentials.dig(:google_calendar, :client_secret)
      
      @auth_client = Signet::OAuth2::Client.new(
        client_id: client_id,
        client_secret: client_secret,
        token_credential_uri: 'https://oauth2.googleapis.com/token',
        access_token: calendar_connection.access_token,
        refresh_token: calendar_connection.refresh_token,
        expires_at: calendar_connection.token_expires_at
      )
      
      @calendar_service.authorization = @auth_client
    end
    
    def build_google_event(event_data)
      Google::Apis::CalendarV3::Event.new(
        summary: event_data[:summary],
        description: event_data[:description],
        location: event_data[:location],
        start: Google::Apis::CalendarV3::EventDateTime.new(
          date_time: event_data[:start_time].iso8601,
          time_zone: business_timezone
        ),
        end: Google::Apis::CalendarV3::EventDateTime.new(
          date_time: event_data[:end_time].iso8601,
          time_zone: business_timezone
        ),
        attendees: event_data[:attendees].map do |attendee|
          Google::Apis::CalendarV3::EventAttendee.new(
            email: attendee[:email],
            display_name: attendee[:display_name],
            response_status: attendee[:response_status],
            organizer: attendee[:organizer]
          )
        end,
        reminders: Google::Apis::CalendarV3::Event::Reminders.new(
          use_default: false,
          overrides: [
            Google::Apis::CalendarV3::EventReminder.new(
              method: 'email',
              minutes: 60
            ),
            Google::Apis::CalendarV3::EventReminder.new(
              method: 'popup',
              minutes: 15
            )
          ]
        )
      )
    end
    
    def fetch_google_events(start_date, end_date)
      time_min = start_date.beginning_of_day.iso8601
      time_max = end_date.end_of_day.iso8601
      
      events_result = @calendar_service.list_events(
        'primary',
        time_min: time_min,
        time_max: time_max,
        single_events: true,
        order_by: 'startTime'
      )
      
      events_result.items.map do |event|
        start_time = parse_google_datetime(event.start)
        end_time = parse_google_datetime(event.end)
        
        next if start_time.nil? || end_time.nil?
        
        {
          external_event_id: event.id,
          external_calendar_id: 'primary',
          starts_at: start_time,
          ends_at: end_time,
          summary: event.summary || 'Untitled Event'
        }
      end.compact
    end
    
    def parse_google_datetime(datetime_obj)
      return nil unless datetime_obj
      
      if datetime_obj.date_time
        Time.parse(datetime_obj.date_time)
      elsif datetime_obj.date
        Date.parse(datetime_obj.date).beginning_of_day
      else
        nil
      end
    rescue ArgumentError
      nil
    end
    
    def find_event_mapping(booking, external_event_id)
      mapping = calendar_connection.calendar_event_mappings
                                 .find_by(booking: booking, external_event_id: external_event_id)
      
      unless mapping
        add_error(:mapping_not_found, "Calendar event mapping not found")
      end
      
      mapping
    end
    
    def handle_api_error(error)
      case error
      when Google::Apis::AuthorizationError
        add_error(:unauthorized, "Google Calendar authorization expired. Please reconnect.")
        deactivate_connection
      when Google::Apis::RateLimitError
        add_error(:rate_limited, "Google Calendar rate limit exceeded. Please try again later.")
      when Google::Apis::ClientError
        add_error(:client_error, "Google Calendar client error: #{error.message}")
      when Google::Apis::ServerError
        add_error(:server_error, "Google Calendar server error. Please try again later.")
      else
        super(error)
      end
    end
  end
end