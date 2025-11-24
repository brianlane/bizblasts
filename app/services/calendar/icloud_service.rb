# frozen_string_literal: true

module Calendar
  class IcloudService < CaldavService
    CALDAV_BASE_URL = 'https://caldav.icloud.com'
    
    def initialize(calendar_connection)
      super(calendar_connection)
      @discovered_calendar_urls = nil
    end
    
    protected
    
    def discover_calendar_url
      # For iCloud, we return all calendar URLs, not just one
      return @discovered_calendar_urls if @discovered_calendar_urls
      
      begin
        # Step 1: Discover principal URL
        principal_url = discover_principal_url
        return nil unless principal_url
        
        # Step 2: Discover calendar home set
        calendar_home_url = discover_calendar_home_set(principal_url)
        return nil unless calendar_home_url
        
        # Step 3: Get ALL calendars that support events
        all_calendar_urls = find_all_event_calendars(calendar_home_url)
        
        @discovered_calendar_urls = all_calendar_urls
      rescue => e
        add_error(:discovery_failed, "Failed to discover iCloud calendars: #{e.message}")
        nil
      end
    end
    
    
    private
    
    def discover_principal_url
      # Use Depth 0 per iCloud CalDAV spec to avoid 400 Bad Request when querying root
      response = propfind_request(CALDAV_BASE_URL, current_user_principal_xml, '0')
      
      unless response.code.to_i.between?(200, 299)
        add_error(:principal_discovery_failed, "Failed to discover principal URL: #{response.message}")
        return nil
      end
      
      # Parse XML response to extract principal URL
      principal_href = extract_href_from_response(response.body, 'current-user-principal')
      
      if principal_href
        principal_href.start_with?('http') ? principal_href : "#{CALDAV_BASE_URL}#{principal_href}"
      else
        add_error(:principal_not_found, "Could not find principal URL in response")
        nil
      end
    end
    
    def discover_calendar_home_set(principal_url)
      response = propfind_request(principal_url, calendar_home_set_xml, '0')
      
      unless response.code.to_i.between?(200, 299)
        add_error(:calendar_home_failed, "Failed to discover calendar home set: #{response.message}")
        return nil
      end
      
      # Parse XML response to extract calendar home set URL
      calendar_home_href = extract_href_from_response(response.body, 'calendar-home-set')
      
      if calendar_home_href
        calendar_home_href.start_with?('http') ? calendar_home_href : "#{CALDAV_BASE_URL}#{calendar_home_href}"
      else
        add_error(:calendar_home_not_found, "Could not find calendar home set in response")
        nil
      end
    end
    
    def find_all_event_calendars(calendar_home_url)
      response = propfind_request(calendar_home_url, calendar_list_xml, '1')
      
      unless response.code.to_i.between?(200, 299)
        add_error(:calendar_list_failed, "Failed to list calendars: #{response.message}")
        return []
      end
      
      # Parse calendars and get ALL that support events
      calendars = parse_calendar_list(response.body)
      
      # Filter to only calendars that support events and are writable
      event_calendars = calendars.select do |cal|
        cal[:supports_events] && cal[:writable]
      end
      
      if event_calendars.any?
        Rails.logger.info("Found #{event_calendars.length} iCloud calendars: #{event_calendars.map { |c| c[:name] }.join(', ')}")
        event_calendars.map { |cal| cal[:url] }
      else
        add_error(:no_calendars_found, "No event calendars found in iCloud account")
        []
      end
    end
    
    def parse_calendar_list(xml_response)
      calendars = []
      doc = Nokogiri::XML(xml_response)
      doc.remove_namespaces!

      doc.xpath('//response').each do |resp_node|
        href = resp_node.at_xpath('href')&.text&.strip
        next unless href&.end_with?('/')

        display_name = resp_node.at_xpath('.//displayname')&.text&.strip || 'Calendar'

        # Identify calendar collections
        is_calendar = resp_node.at_xpath('.//resourcetype/calendar').present?

        # Determine component support (look for VEVENT inside supported set)
        supports_events = resp_node.to_xml.match?(/VEVENT/i)

        # Writable unless privilege explicitly denies write
        writable = !resp_node.to_xml.match?(/<need-privileges/i) || resp_node.to_xml.match?(/<write/i)

        next unless is_calendar

        full_url = href.start_with?('http') ? href : "#{CALDAV_BASE_URL}#{href}"

        calendars << {
          url: full_url,
          name: display_name,
          supports_events: supports_events,
          writable: writable
        }
      end

      calendars
    end
    
    def extract_href_from_response(xml_response, element_name)
      # Use Nokogiri for robust namespace-agnostic parsing
      doc = Nokogiri::XML(xml_response)
      doc.remove_namespaces!
      case element_name
      when 'current-user-principal'
        doc.at_xpath('//current-user-principal/href')&.text&.strip
      when 'calendar-home-set'
        doc.at_xpath('//calendar-home-set/href')&.text&.strip
      else
        nil
      end
    end
    
    def current_user_principal_xml
      <<~XML
        <?xml version="1.0" encoding="utf-8" ?>
        <D:propfind xmlns:D="DAV:">
          <D:prop>
            <D:current-user-principal />
          </D:prop>
        </D:propfind>
      XML
    end
    
    def calendar_home_set_xml
      <<~XML
        <?xml version="1.0" encoding="utf-8" ?>
        <D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
          <D:prop>
            <C:calendar-home-set />
          </D:prop>
        </D:propfind>
      XML
    end
    
    def calendar_list_xml
      <<~XML
        <?xml version="1.0" encoding="utf-8" ?>
        <D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav" xmlns:ICAL="http://apple.com/ns/ical/">
          <D:prop>
            <D:resourcetype />
            <D:displayname />
            <ICAL:calendar-color />
            <C:supported-calendar-component-set />
            <D:getctag />
            <D:current-user-privilege-set />
          </D:prop>
        </D:propfind>
      XML
    end
    
    # Override headers for iCloud-specific requirements
    def propfind_headers(depth = '1')
      super(depth).merge({
        'User-Agent' => 'BizBlasts Calendar Sync/1.0 (CalDAV)',
        'Accept' => 'application/xml, text/xml'
      })
    end
    
    def put_headers(is_new_event = false)
      super(is_new_event).merge({
        'User-Agent' => 'BizBlasts Calendar Sync/1.0 (CalDAV)'
      })
    end
  end
end