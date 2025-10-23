# frozen_string_literal: true

require 'httparty'
require 'icalendar'
require 'net/http'
require 'uri'

module Calendar
  class CaldavService < BaseService
    include HTTParty
    
    attr_reader :username, :password, :server_url
    
    def initialize(calendar_connection)
      super(calendar_connection)
      @username = calendar_connection.caldav_username
      @password = calendar_connection.caldav_password
      @server_url = calendar_connection.caldav_url
      @calendar_url = nil
      
      validate_credentials
    end
    
    # Override OAuth-specific methods from BaseService
    def refresh_access_token
      # CalDAV doesn't use refresh tokens
      true
    end
    
    def create_event(booking)
      return false unless validate_booking(booking) && validate_connection
      
      with_error_handling do
        calendar_urls = discover_calendar_url
        return false unless calendar_urls.present?
        
        # For event creation, choose the best calendar for user events
        primary_calendar_url = select_primary_calendar_for_events(calendar_urls)
        
        # Check if event already exists
        mapping = CalendarEventMapping.find_by(
          booking: booking,
          calendar_connection: calendar_connection
        )
        
        event_uid = mapping&.external_event_id || generate_event_uid(booking)
        ical_data = build_ical_event(booking, event_uid)
        
        result = if mapping
          update_caldav_event(event_uid, ical_data, primary_calendar_url)
        else
          create_caldav_event(event_uid, ical_data, primary_calendar_url)
        end
        
        if result
          # Create or update mapping
          mapping ||= CalendarEventMapping.new(
            calendar_connection: calendar_connection,
            booking: booking
          )
          
          mapping.update!(
            external_event_id: event_uid,
            external_calendar_id: primary_calendar_url,
            status: :synced,
            last_synced_at: Time.current
          )
          
          calendar_connection.mark_synced!
          true
        else
          false
        end
      end
    end
    
    def update_event(booking, external_event_id)
      return false unless validate_booking(booking) && validate_connection
      
      with_error_handling do
        calendar_urls = discover_calendar_url
        return false unless calendar_urls.present?
        
        # For updates, use the calendar from the existing mapping if available
        mapping = CalendarEventMapping.find_by(
          booking: booking,
          calendar_connection: calendar_connection
        )
        
        calendar_url = mapping&.external_calendar_id || select_primary_calendar_for_events(calendar_urls)
        ical_data = build_ical_event(booking, external_event_id)
        
        if update_caldav_event(external_event_id, ical_data, calendar_url)
          mapping&.update!(
            status: :synced,
            last_synced_at: Time.current
          )
          
          calendar_connection.mark_synced!
          true
        else
          false
        end
      end
    end
    
    def delete_event(external_event_id)
      return false unless validate_connection
      
      with_error_handling do
        calendar_urls = discover_calendar_url
        return false unless calendar_urls.present?
        
        # For deletion, try to find the event in the calendar where it was created
        mapping = CalendarEventMapping.find_by(external_event_id: external_event_id, calendar_connection: calendar_connection)
        calendar_url = mapping&.external_calendar_id || select_primary_calendar_for_events(calendar_urls)
        
        event_url = "#{calendar_url.chomp('/')}/#{external_event_id}.ics"
        response = delete_request(event_url)
        
        if [200, 204, 404].include?(response.code.to_i)
          calendar_connection.mark_synced!
          true
        else
          add_error(:delete_failed, "Failed to delete event: #{response.message}")
          false
        end
      end
    end
    
    def import_events(start_date, end_date)
      return { success: false, imported_count: 0, errors: ["Invalid connection"] } unless validate_connection

      with_error_handling do
        calendar_urls = discover_calendar_url
        return { success: false, imported_count: 0, errors: ["No calendar URLs discovered"] } if calendar_urls.blank?

        all_events = []
        calendar_urls.each do |calendar_url|
          raw_response = fetch_events_in_range(calendar_url, start_date, end_date)
          events = parse_imported_events(raw_response)
          
          # Add calendar_url to each event for tracking
          events.each do |event|
            event[:source_calendar_url] = calendar_url
          end
          
          all_events.concat(events)
        end

        # Transform to ExternalCalendarEvent schema
        formatted = all_events.map do |e|
          {
            external_event_id: e[:uid],
            external_calendar_id: e[:source_calendar_url],
            starts_at: e[:start_time],
            ends_at:   e[:end_time],
            summary:   e[:summary]
          }
        end

        import_result = ExternalCalendarEvent.import_for_connection(calendar_connection, formatted)
        calendar_connection.mark_synced!

        {
          success: true,
          imported_count: import_result[:imported_count],
          errors: import_result[:errors]
        }
      end || { success: false, imported_count: 0, errors: ["Unknown error"] }
    end
    
    def test_connection
      begin
        calendar_urls = discover_calendar_url
        
        if calendar_urls.present?
          {
            success: true,
            message: "Successfully connected to #{calendar_connection.caldav_provider_display_name} (#{calendar_urls.length} calendars found)",
            calendar_urls: calendar_urls
          }
        else
          {
            success: false,
            message: "Failed to discover calendar URLs",
            errors: @errors.full_messages
          }
        end
      rescue => e
        {
          success: false,
          message: "Connection failed: #{e.message}",
          error_type: classify_caldav_error(e)
        }
      end
    end
    
    protected
    
    # Abstract method to be implemented by provider-specific subclasses
    def discover_calendar_url
      raise NotImplementedError, "Subclass must implement discover_calendar_url"
    end
    
    def validate_credentials
      unless @username.present? && @password.present?
        add_error(:missing_credentials, "CalDAV username and password are required")
        return false
      end
      true
    end
    
    def validate_connection
      return false unless super
      return false unless validate_credentials
      true
    end
    
    def generate_event_uid(booking)
      "bizblasts-#{booking.id}-#{SecureRandom.hex(8)}"
    end
    
    def select_primary_calendar_for_events(calendar_urls)
      return calendar_urls.first unless calendar_urls.length > 1
      
      # Preferred calendar names for event creation (in order of preference)
      # Try 'work' first as 'home' might have write restrictions in some iCloud setups
      preferred_names = ['work', 'calendar', 'personal', 'main', 'default', 'home']
      
      # Try to find a calendar with a preferred name (in order of preference)
      preferred_calendar = nil
      preferred_names.each do |name|
        preferred_calendar = calendar_urls.find { |url| url.downcase.include?("/#{name}/") }
        break if preferred_calendar
      end
      
      # If found a preferred calendar, use it; otherwise use the first one
      preferred_calendar || calendar_urls.first
    end
    
    def create_caldav_event(event_uid, ical_data, calendar_url)
      # Ensure no double slashes in URL construction
      event_url = "#{calendar_url.chomp('/')}/#{event_uid}.ics"
      response = put_request(event_url, ical_data, true) # true indicates new event
      
      if [200, 201, 204].include?(response.code.to_i)
        true
      else
        add_error(:create_failed, "Failed to create event: #{response.message}")
        false
      end
    end
    
    def update_caldav_event(event_uid, ical_data, calendar_url)
      # Ensure no double slashes in URL construction
      event_url = "#{calendar_url.chomp('/')}/#{event_uid}.ics"
      response = put_request(event_url, ical_data, false) # false indicates update, not new
      
      if [200, 204].include?(response.code.to_i)
        true
      else
        add_error(:update_failed, "Failed to update event: #{response.message}")
        false
      end
    end
    
    def fetch_events_in_range(calendar_url, start_date, end_date)
      # REPORT request for calendar data in date range
      report_body = build_calendar_query(start_date, end_date)
      
      response = report_request(calendar_url, report_body)
      
      if response.code.to_i.between?(200, 299)
        response.body
      else
        add_error(:import_failed, "Failed to fetch events: #{response.message}")
        nil
      end
    end
    
    def build_ical_event(booking, event_uid)
      formatted_booking = format_booking_for_calendar(booking)
      
      # Convert times to UTC for better CalDAV compatibility
      start_utc = formatted_booking[:start_time].utc
      end_utc = formatted_booking[:end_time].utc
      
      # Build minimal but complete iCal event for maximum compatibility
      ical_content = <<~ICAL
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//BizBlasts//Calendar Integration//EN
        CALSCALE:GREGORIAN
        BEGIN:VEVENT
        UID:#{event_uid}
        DTSTAMP:#{Time.current.utc.strftime('%Y%m%dT%H%M%SZ')}
        DTSTART:#{start_utc.strftime('%Y%m%dT%H%M%SZ')}
        DTEND:#{end_utc.strftime('%Y%m%dT%H%M%SZ')}
        SUMMARY:#{formatted_booking[:summary]}
        STATUS:CONFIRMED
        TRANSP:OPAQUE
        END:VEVENT
        END:VCALENDAR
      ICAL
      
      ical_content
    end
    
    def build_calendar_query(start_date, end_date)
      # Use business timezone for the calendar query, not UTC
      tz = business_timezone
      start_time = start_date.beginning_of_day.in_time_zone(tz).utc.strftime('%Y%m%dT%H%M%SZ')
      end_time = end_date.end_of_day.in_time_zone(tz).utc.strftime('%Y%m%dT%H%M%SZ')
      
      <<~XML
        <?xml version="1.0" encoding="utf-8" ?>
        <C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
          <D:prop>
            <D:getetag />
            <C:calendar-data />
          </D:prop>
          <C:filter>
            <C:comp-filter name="VCALENDAR">
              <C:comp-filter name="VEVENT">
                <C:time-range start="#{start_time}" end="#{end_time}"/>
              </C:comp-filter>
            </C:comp-filter>
          </C:filter>
        </C:calendar-query>
      XML
    end
    
    def parse_imported_events(response_data)
      return [] unless response_data.present?

      calendars = []

      begin
        doc = Nokogiri::XML(response_data)
        doc.remove_namespaces!
        doc.xpath('//calendar-data').each do |cal_node|
          calendars << cal_node.text
        end
      rescue Nokogiri::XML::SyntaxError
        # Fallback to safer pattern matching if XML malformed
        # Use more specific pattern to prevent ReDoS - match line by line instead of greedy .*?
        # Split by BEGIN:VCALENDAR and reconstruct blocks
        blocks = response_data.split('BEGIN:VCALENDAR')
        blocks.shift if blocks.first && !blocks.first.include?('END:VCALENDAR')

        blocks.each do |block|
          if block.include?('END:VCALENDAR')
            # Extract up to END:VCALENDAR (take first occurrence)
            end_index = block.index('END:VCALENDAR')
            if end_index
              calendar_block = 'BEGIN:VCALENDAR' + block[0..end_index + 'END:VCALENDAR'.length - 1]
              calendars << calendar_block
            end
          end
        end
      end

      events = []
      calendars.each do |ical_text|
        begin
          parsed = Icalendar::Calendar.parse(ical_text).first
          parsed.events.each do |evt|
            events << {
              uid: evt.uid.to_s,
              summary: evt.summary.to_s,
              start_time: evt.dtstart.to_time,
              end_time: evt.dtend.to_time,
              description: evt.description.to_s
            }
          end
        rescue => e
          Rails.logger.warn("iCal parse error: #{e.message}")
        end
      end

      events
    end
    
    def put_request(url, body, is_new_event = false)
      HTTParty.put(
        url,
        body: body,
        headers: put_headers(is_new_event),
        basic_auth: auth_credentials,
        timeout: 30
      )
    end
    
    def delete_request(url)
      HTTParty.delete(
        url,
        basic_auth: auth_credentials,
        timeout: 30
      )
    end
    
    def propfind_request(url, body, depth = '1')
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = 30
      
      path = uri.path.empty? ? '/' : uri.path
      request = Net::HTTPGenericRequest.new('PROPFIND', true, true, path)
      request.basic_auth(@username, @password)
      request.body = body
      
      propfind_headers(depth).each do |key, value|
        request[key] = value
      end
      
      http.request(request)
    end
    
    def report_request(url, body)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = 30
      
      path = uri.path.empty? ? '/' : uri.path
      request = Net::HTTPGenericRequest.new('REPORT', true, true, path)
      request.basic_auth(@username, @password)
      request.body = body
      
      report_headers.each do |key, value|
        request[key] = value
      end
      
      http.request(request)
    end
    
    def auth_credentials
      { username: @username, password: @password }
    end
    
    def put_headers(is_new_event = false)
      headers = {
        'Content-Type' => 'text/calendar; charset=utf-8',
        'User-Agent' => user_agent
      }
      
      # Add If-None-Match header for new event creation to prevent overwrites
      headers['If-None-Match'] = '*' if is_new_event
      
      headers
    end
    
    def propfind_headers(depth = '1')
      {
        'Content-Type' => 'application/xml; charset=utf-8',
        'Depth' => depth,
        'User-Agent' => user_agent
      }
    end
    
    def report_headers
      {
        'Content-Type' => 'application/xml; charset=utf-8',
        'Depth' => '1',
        'User-Agent' => user_agent
      }
    end
    
    def user_agent
      'BizBlasts Calendar Sync/1.0'
    end
    
    def classify_caldav_error(error)
      case error.message.downcase
      when /401/, /unauthorized/
        :authentication_failed
      when /403/, /forbidden/
        :access_denied
      when /404/, /not found/
        :calendar_not_found
      when /timeout/
        :connection_timeout
      when /ssl/, /certificate/
        :ssl_error
      when /network/, /connection/
        :network_error
      else
        :unknown_error
      end
    end
  end
end