# frozen_string_literal: true

module Calendar
  class GenericCaldavService < CaldavService
    def initialize(calendar_connection)
      super(calendar_connection)
      @discovered_calendar_urls = nil
    end
    
    protected
    
    def discover_calendar_url
      return @discovered_calendar_urls if @discovered_calendar_urls
      
      begin
        # If a specific calendar URL is provided, try to use it directly
        if @server_url.present?
          # Check if the URL points directly to a calendar collection
          if calendar_collection?(@server_url)
            @discovered_calendar_urls = [@server_url]
            return @discovered_calendar_urls
          end
          
          # Try to discover calendars from the provided URL
          calendars = discover_calendars_from_url(@server_url)
          
          if calendars.any?
            # Get ALL writable calendars that support events
            event_calendars = calendars.select { |cal| cal[:writable] && cal[:supports_events] }
            @discovered_calendar_urls = event_calendars.map { |cal| cal[:url] }
          else
            @discovered_calendar_urls = []
          end
        else
          @discovered_calendar_urls = []
        end
        
        @discovered_calendar_urls
      rescue => e
        add_error(:discovery_failed, "Failed to discover CalDAV calendars: #{e.message}")
        []
      end
    end
    
    private
    
    def calendar_collection?(url)
      return false unless url.present?
      
      begin
        response = propfind_request(url, calendar_check_xml, '0')
        
        if response.code.to_i.between?(200, 299)
          # Check if the response indicates this is a calendar collection
          response.body.include?('calendar') && 
          (response.body.include?('collection') || response.body.include?('VEVENT'))
        else
          false
        end
      rescue
        false
      end
    end
    
    def discover_calendars_from_url(base_url)
      calendars = []
      
      # Try different discovery methods
      
      # Method 1: PropFind on the base URL
      calendars = try_propfind_discovery(base_url)
      return calendars if calendars.any?
      
      # Method 2: Try common CalDAV paths
      common_paths = [
        '/calendars/',
        '/cal/',
        '/calendar/',
        '/dav/calendars/',
        '/caldav/'
      ]
      
      base_uri = URI.parse(base_url)
      base_without_path = "#{base_uri.scheme}://#{base_uri.host}"
      base_without_path += ":#{base_uri.port}" if base_uri.port != base_uri.default_port
      
      common_paths.each do |path|
        test_url = "#{base_without_path}#{path}"
        discovered = try_propfind_discovery(test_url)
        if discovered.any?
          calendars = discovered
          break
        end
      end
      
      calendars
    end
    
    def try_propfind_discovery(url)
      calendars = []
      
      begin
        response = propfind_request(url, calendar_list_xml, '1')
        
        if response.code.to_i.between?(200, 299)
          calendars = parse_generic_calendar_list(response.body, url)
        end
      rescue => e
        Rails.logger.debug("Discovery failed for #{url}: #{e.message}")
      end
      
      calendars
    end
    
    def parse_generic_calendar_list(xml_response, base_url)
      calendars = []

      # Use Nokogiri XML parser instead of regex to prevent ReDoS attacks
      doc = Nokogiri::XML(xml_response)
      doc.remove_namespaces! # Simplify XPath queries

      base_path = URI.parse(base_url).path

      # Parse each response element
      doc.xpath('//response').each do |response_node|
        # Extract href
        href = response_node.at_xpath('./href')&.text&.strip
        next if href.blank?

        # Skip if it's the same as base URL or doesn't end with /
        next unless href.end_with?('/') && href != base_path

        # Extract display name - handle both CDATA and plain text
        display_name_node = response_node.at_xpath('./propstat/prop/displayname')
        display_name = if display_name_node
          # Get text content, which automatically handles CDATA
          display_name_node.text.strip
        else
          File.basename(href, '/')
        end

        # Check if it's a calendar
        resourcetype = response_node.at_xpath('./propstat/prop/resourcetype')&.to_s || ''
        is_calendar = resourcetype.include?('calendar') ||
                     resourcetype.include?('VEVENT') ||
                     resourcetype.include?('resourcetype')

        # Check if it supports events
        component_set = response_node.at_xpath('./propstat/prop/supported-calendar-component-set')&.to_s || ''
        supports_events = component_set.empty? || component_set.include?('VEVENT')

        # Assume writable unless explicitly denied
        privilege_set = response_node.at_xpath('./propstat/prop/current-user-privilege-set')&.to_s || ''
        writable = !privilege_set.include?('need-privileges') ||
                  privilege_set.include?('write')

        if is_calendar
          base_uri = URI.parse(base_url)
          full_url = href.start_with?('http') ? href : "#{base_uri.scheme}://#{base_uri.host}#{href}"

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
      Rails.logger.error("Failed to parse generic CalDAV calendar list XML: #{e.message}")
      []
    end
    
    def calendar_check_xml
      <<~XML
        <?xml version="1.0" encoding="utf-8" ?>
        <D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
          <D:prop>
            <D:resourcetype />
            <C:supported-calendar-component-set />
          </D:prop>
        </D:propfind>
      XML
    end
    
    def calendar_list_xml
      <<~XML
        <?xml version="1.0" encoding="utf-8" ?>
        <D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
          <D:prop>
            <D:resourcetype />
            <D:displayname />
            <C:calendar-description />
            <C:supported-calendar-component-set />
            <D:getctag />
            <D:current-user-privilege-set />
          </D:prop>
        </D:propfind>
      XML
    end
    
    # Generic headers - less specific than provider implementations
    def propfind_headers(depth = '1')
      super(depth).merge({
        'User-Agent' => 'BizBlasts Calendar Sync/1.0 (Generic CalDAV)'
      })
    end
    
    def put_headers(is_new_event = false)
      super(is_new_event).merge({
        'User-Agent' => 'BizBlasts Calendar Sync/1.0 (Generic CalDAV)'
      })
    end
    
    # Enhanced validation for generic CalDAV
    def validate_credentials
      return false unless super
      
      unless @server_url.present?
        add_error(:missing_url, "CalDAV server URL is required for generic CalDAV connections")
        return false
      end
      
      # Basic URL validation
      begin
        uri = URI.parse(@server_url)
        unless uri.scheme && uri.host
          add_error(:invalid_url, "Invalid CalDAV server URL format")
          return false
        end
      rescue URI::InvalidURIError
        add_error(:invalid_url, "Invalid CalDAV server URL")
        return false
      end
      
      true
    end
    
    # Enhanced error classification for generic servers
    def classify_caldav_error(error)
      case error.message.downcase
      when /method not allowed/
        :method_not_supported
      when /precondition failed/
        :precondition_failed
      when /conflict/
        :conflict
      else
        super
      end
    end
  end
end