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

        # Remove events that were deleted from Google Calendar
        remote_ids = events.map { |e| e[:external_event_id] }
        stale_events = calendar_connection.external_calendar_events
                                         .where(starts_at: start_date.beginning_of_day..end_date.end_of_day)
                                         .where.not(external_event_id: remote_ids)
        stale_events.find_each(&:destroy)
        
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
      
      # Use dev credentials in development/test environments
      if Rails.env.development? || Rails.env.test?
        client_id = ENV['GOOGLE_CALENDAR_CLIENT_ID_DEV']
        client_secret = ENV['GOOGLE_CALENDAR_CLIENT_SECRET_DEV']
      else
        client_id = ENV['GOOGLE_CALENDAR_CLIENT_ID']
        client_secret = ENV['GOOGLE_CALENDAR_CLIENT_SECRET']
      end
      
      # Skip setup if credentials are missing (common in tests)
      unless client_id && client_secret
        Rails.logger.warn("Google Calendar credentials not configured, skipping authorization setup")
        return
      end
      
      begin
        @auth_client = Signet::OAuth2::Client.new(
          client_id: client_id,
          client_secret: client_secret,
          token_credential_uri: 'https://oauth2.googleapis.com/token',
          access_token: calendar_connection.access_token,
          refresh_token: calendar_connection.refresh_token,
          expires_at: calendar_connection.token_expires_at
        )
        
        # Enable automatic token refresh
        @auth_client.update_token_callback = proc do |token_data|
          calendar_connection.update!(
            access_token: token_data[:access_token],
            token_expires_at: Time.at(token_data[:expires_at]) || 1.hour.from_now
          )
          Rails.logger.info("Google Calendar token auto-refreshed for connection #{calendar_connection.id}")
        end
        
        @calendar_service.authorization = @auth_client
      rescue => e
        Rails.logger.warn("Failed to setup Google Calendar authorization: #{e.message}")
        add_error(:authorization_setup_failed, "Failed to setup calendar authorization")
      end
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
        datetime_val = datetime_obj.date_time
        datetime_val = datetime_val.to_s if datetime_val.is_a?(DateTime)
        Time.parse(datetime_val.to_s)
      elsif datetime_obj.date
        # "date" may already be a Date object or a String (YYYY-MM-DD)
        date_val = datetime_obj.date.is_a?(String) ? Date.parse(datetime_obj.date) : datetime_obj.date
        date_val.to_time
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
        # Try to refresh token before giving up
        if calendar_connection.needs_refresh?
          Rails.logger.info("Attempting to refresh expired Google Calendar token for connection #{calendar_connection.id}")
          if refresh_access_token
            Rails.logger.info("Token refresh successful, retrying API call")
            return :retry_request
          end
        end
        
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