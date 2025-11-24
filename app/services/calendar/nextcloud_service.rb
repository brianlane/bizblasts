# frozen_string_literal: true

module Calendar
  class NextcloudService < CaldavService
    def initialize(calendar_connection)
      super(calendar_connection)
      @base_url = normalize_base_url(calendar_connection.caldav_url)
      @discovered_calendar_urls = nil
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

      # Use Nokogiri XML parser instead of regex to prevent ReDoS attacks
      doc = Nokogiri::XML(xml_response)
      doc.remove_namespaces! # Simplify XPath queries

      # Parse each response element
      doc.xpath('//response').each do |response_node|
        # Extract href (calendar URL)
        href = response_node.at_xpath('./href')&.text&.strip
        next unless href.present? && href.end_with?('/')
        next if href == base_url.gsub(@base_url, '') # Skip the parent collection

        # Extract display name - handle both CDATA and plain text
        display_name_node = response_node.at_xpath('./propstat/prop/displayname')
        display_name = if display_name_node
          # Get text content, which automatically handles CDATA
          display_name_node.text.strip
        else
          File.basename(href, '/')
        end

        # Check if it's a calendar collection
        resourcetype = response_node.at_xpath('./propstat/prop/resourcetype')&.to_s || ''
        # Identify calendar collections strictly: must advertise both "calendar" and "collection".
        is_calendar = resourcetype.include?('calendar') && resourcetype.include?('collection')

        # Check if it supports VEVENT (calendar events)
        component_set = response_node.at_xpath('./propstat/prop/supported-calendar-component-set')&.to_s || ''
        supports_events = component_set.include?('VEVENT') || component_set.empty?

        # Check write permissions
        privilege_set = response_node.at_xpath('./propstat/prop/current-user-privilege-set')&.to_s || ''
        writable = !privilege_set.include?('need-privileges') ||
                  privilege_set.include?('write') ||
                  privilege_set.include?('write-content')

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
    rescue Nokogiri::XML::SyntaxError => e
      Rails.logger.error("Failed to parse Nextcloud calendar list XML: #{e.message}")
      []
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
    
    def put_headers(is_new_event = false)
      super(is_new_event).merge({
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