# frozen_string_literal: true

module Calendar
  class NextcloudService < CaldavService
    def initialize(calendar_connection)
      super(calendar_connection)
      @base_url = normalize_base_url(calendar_connection.caldav_url)
      @discovered_calendar_url = nil
    end
    
    protected
    
    def discover_calendar_url
      return @discovered_calendar_urls if @discovered_calendar_urls
      
      begin
        # For Nextcloud, we can construct the calendar home URL directly
        calendar_home_url = "#{@base_url}/remote.php/dav/calendars/#{@username}/"
        
        # Find ALL calendars that support events
        all_calendar_urls = find_all_event_calendars(calendar_home_url)
        
        @discovered_calendar_urls = all_calendar_urls
      rescue => e
        add_error(:discovery_failed, "Failed to discover Nextcloud calendars: #{e.message}")
        []
      end
    end
    
    private
    
    def normalize_base_url(url)
      return nil unless url.present?
      
      # Remove trailing slashes and path components
      uri = URI.parse(url)
      base_url = "#{uri.scheme}://#{uri.host}"
      base_url += ":#{uri.port}" if uri.port && uri.port != uri.default_port
      base_url
    end
    
    def find_all_event_calendars(calendar_home_url)
      response = propfind_request(calendar_home_url, calendar_list_xml, '1')
      
      unless response.code.to_i.between?(200, 299)
        add_error(:calendar_list_failed, "Failed to list Nextcloud calendars: #{response.message}")
        return []
      end
      
      # Parse calendars and get ALL that support events
      calendars = parse_calendar_list(response.body, calendar_home_url)
      
      # Filter to only calendars that support events and are writable
      event_calendars = calendars.select do |cal|
        cal[:supports_events] && cal[:writable]
      end
      
      if event_calendars.any?
        Rails.logger.info("Found #{event_calendars.length} Nextcloud calendars: #{event_calendars.map { |c| c[:name] }.join(', ')}")
        event_calendars.map { |cal| cal[:url] }
      else
        add_error(:no_calendars_found, "No event calendars found in Nextcloud account")
        []
      end
    end
    
    def parse_calendar_list(xml_response, base_url)
      calendars = []
      
      # Parse Nextcloud calendar list from PropFind response
      xml_response.scan(/<D:response>(.*?)<\/D:response>/m).each do |response_match|
        response_xml = response_match[0]
        
        # Extract href (calendar URL)
        href_match = response_xml.match(/<D:href>(.*?)<\/D:href>/)
        next unless href_match
        
        href = href_match[1].strip
        next unless href.end_with?('/')
        next if href == base_url.gsub(@base_url, '') # Skip the parent collection
        
        # Extract display name
        display_name_match = response_xml.match(/<D:displayname><!\[CDATA\[(.*?)\]\]><\/D:displayname>/) ||
                            response_xml.match(/<D:displayname>(.*?)<\/D:displayname>/)
        display_name = display_name_match ? display_name_match[1].strip : File.basename(href, '/')
        
        # Check if it's a calendar collection
        is_calendar = response_xml.include?('calendar') && 
                     (response_xml.include?('collection') || response_xml.include?('resourcetype'))
        
        # Check if it supports VEVENT (calendar events)
        supports_events = response_xml.include?('VEVENT') || 
                         !response_xml.include?('supported-calendar-component-set')
        
        # Check write permissions
        writable = !response_xml.include?('need-privileges') || 
                  response_xml.include?('write') ||
                  response_xml.include?('write-content')
        
        if is_calendar
          full_url = href.start_with?('http') ? href : "#{@base_url}#{href}"
          
          calendars << {
            url: full_url,
            name: display_name,
            supports_events: supports_events,
            writable: writable
          }
        end
      end
      
      calendars
    end
    
    def calendar_list_xml
      <<~XML
        <?xml version="1.0" encoding="utf-8" ?>
        <D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav" xmlns:CS="http://nextcloud.com/ns">
          <D:prop>
            <D:resourcetype />
            <D:displayname />
            <C:calendar-description />
            <C:supported-calendar-component-set />
            <D:getctag />
            <CS:calendar-color />
            <D:current-user-privilege-set />
          </D:prop>
        </D:propfind>
      XML
    end
    
    # Override headers for Nextcloud-specific requirements
    def propfind_headers(depth = '1')
      super(depth).merge({
        'User-Agent' => 'BizBlasts Calendar Sync/1.0 (Nextcloud CalDAV)',
        'Accept' => 'application/xml, text/xml',
        'Content-Type' => 'application/xml; charset=utf-8'
      })
    end
    
    def put_headers
      super.merge({
        'User-Agent' => 'BizBlasts Calendar Sync/1.0 (Nextcloud CalDAV)'
      })
    end
    
    def report_headers
      super.merge({
        'User-Agent' => 'BizBlasts Calendar Sync/1.0 (Nextcloud CalDAV)'
      })
    end
    
    # Nextcloud-specific error handling
    def classify_caldav_error(error)
      case error.message.downcase
      when /sabre\\dav\\exception\\forbidden/
        :access_denied
      when /sabre\\dav\\exception\\notfound/
        :calendar_not_found
      when /app.*password.*required/
        :app_password_required
      else
        super
      end
    end
    
    # Additional validation for Nextcloud
    def validate_credentials
      return false unless super
      
      # Check if base URL looks like a Nextcloud instance
      if @server_url.present? && !@server_url.include?('nextcloud') && !@server_url.include?('remote.php')
        Rails.logger.warn("URL doesn't appear to be a Nextcloud instance: #{@server_url}")
      end
      
      true
    end
  end
end