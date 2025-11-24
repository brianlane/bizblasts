# frozen_string_literal: true

module Calendar
  class MicrosoftService < BaseService
    require 'microsoft_graph'
    require 'oauth2'
    
    def initialize(calendar_connection)
      super(calendar_connection)
      setup_microsoft_client
    end
    
    def create_event(booking)
      return nil unless validate_booking(booking) && validate_connection
      
      with_error_handling do
        event_data = format_booking_for_calendar(booking)
        microsoft_event = build_microsoft_event(event_data)
        
        response = @graph_client.me.events.post(microsoft_event)
        
        if response && response['id']
          # Create mapping record
          mapping = CalendarEventMapping.create!(
            booking: booking,
            calendar_connection: calendar_connection,
            external_event_id: response['id'],
            external_calendar_id: 'primary',
            status: :synced,
            last_synced_at: Time.current
          )
          
          # Update booking calendar status
          booking.update!(
            calendar_event_status: :synced,
            calendar_event_id: response['id']
          )
          
          log_sync_attempt(mapping, :event_create, :success, "Event created successfully")
          
          {
            success: true,
            external_event_id: response['id'],
            mapping: mapping
          }
        else
          add_error(:creation_failed, "Failed to create Microsoft Calendar event")
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
        microsoft_event = build_microsoft_event(event_data)
        
        response = @graph_client.me.events[external_event_id].patch(microsoft_event)
        
        if response && response['id']
          mapping.mark_synced!(external_event_id)
          booking.update!(calendar_event_status: :synced)
          
          log_sync_attempt(mapping, :event_update, :success, "Event updated successfully")
          
          {
            success: true,
            external_event_id: response['id'],
            mapping: mapping
          }
        else
          add_error(:update_failed, "Failed to update Microsoft Calendar event")
          mapping.mark_failed!("Update failed")
          nil
        end
      end
    end
    
    def delete_event(external_event_id)
      return nil unless validate_connection
      
      with_error_handling do
        @graph_client.me.events[external_event_id].delete
        
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
        events = fetch_microsoft_events(start_date, end_date)
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
        setup_microsoft_client
        true
      else
        oauth_handler.errors.each do |error|
          add_error(error.attribute, error.message)
        end
        false
      end
    end
    
    private
    
    def setup_microsoft_client
      return unless calendar_connection.access_token
      
      begin
        @graph_client = MicrosoftGraph.new(
          base_url: 'https://graph.microsoft.com/v1.0',
          access_token: calendar_connection.access_token
        )
      rescue => e
        Rails.logger.error("Failed to setup Microsoft Graph client: #{e.message}")
        add_error(:client_setup_failed, "Failed to setup Microsoft Graph client")
      end
    end
    
    def build_microsoft_event(event_data)
      {
        subject: event_data[:summary],
        body: {
          content_type: 'text',
          content: event_data[:description]
        },
        start: {
          date_time: event_data[:start_time].iso8601,
          time_zone: business_timezone
        },
        end: {
          date_time: event_data[:end_time].iso8601,
          time_zone: business_timezone
        },
        location: {
          display_name: event_data[:location]
        },
        attendees: event_data[:attendees].map do |attendee|
          {
            email_address: {
              address: attendee[:email],
              name: attendee[:display_name]
            },
            type: attendee[:organizer] ? 'required' : 'optional'
          }
        end,
        reminder_minutes_before_start: 60,
        is_reminder_on: true
      }
    end
    
    def fetch_microsoft_events(start_date, end_date)
      start_time = start_date.beginning_of_day.iso8601
      end_time = end_date.end_of_day.iso8601
      
      # Build OData query parameters
      filter = "$filter=start/dateTime ge '#{start_time}' and end/dateTime le '#{end_time}'"
      select = "$select=id,subject,start,end,location"
      orderby = "$orderby=start/dateTime"
      
      query_params = "#{filter}&#{select}&#{orderby}"
      
      response = @graph_client.me.events.get(query_params)
      events = response['value'] || []
      
      events.map do |event|
        start_time = parse_microsoft_datetime(event['start'])
        end_time = parse_microsoft_datetime(event['end'])
        
        next if start_time.nil? || end_time.nil?
        
        {
          external_event_id: event['id'],
          external_calendar_id: 'primary',
          starts_at: start_time,
          ends_at: end_time,
          summary: event['subject'] || 'Untitled Event'
        }
      end.compact
    rescue => e
      Rails.logger.error("Failed to fetch Microsoft calendar events: #{e.message}")
      []
    end
    
    def parse_microsoft_datetime(datetime_obj)
      return nil unless datetime_obj && datetime_obj['dateTime']
      
      Time.parse(datetime_obj['dateTime'])
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
      when OAuth2::Error
        if error.code == 'invalid_grant' || error.code == 'unauthorized'
          add_error(:unauthorized, "Microsoft Calendar authorization expired. Please reconnect.")
          deactivate_connection
        elsif error.code == 'throttled_request'
          add_error(:rate_limited, "Microsoft Graph rate limit exceeded. Please try again later.")
        else
          add_error(:api_error, "Microsoft Graph API error: #{error.description || error.message}")
        end
      when Net::HTTPUnauthorized
        add_error(:unauthorized, "Microsoft Calendar authorization expired. Please reconnect.")
        deactivate_connection
      when Net::HTTPTooManyRequests
        add_error(:rate_limited, "Microsoft Graph rate limit exceeded. Please try again later.")
      when Net::HTTPBadRequest
        add_error(:bad_request, "Invalid request to Microsoft Graph: #{error.message}")
      when Net::HTTPServerError
        add_error(:server_error, "Microsoft Graph server error. Please try again later.")
      else
        super(error)
      end
    end
  end
end