# frozen_string_literal: true

module Calendar
  class CaldavFactory
    # Factory method to create the appropriate CalDAV service
    def self.create_service(calendar_connection)
      unless calendar_connection.caldav_provider?
        raise ArgumentError, "Calendar connection must be a CalDAV provider"
      end
      
      provider = detect_provider(calendar_connection)
      
      case provider
      when :icloud
        Calendar::IcloudService.new(calendar_connection)
      when :nextcloud
        Calendar::NextcloudService.new(calendar_connection)
      when :generic
        Calendar::GenericCaldavService.new(calendar_connection)
      else
        # Fallback to generic service
        Calendar::GenericCaldavService.new(calendar_connection)
      end
    end
    
    # Test a CalDAV connection before creating it
    def self.test_connection(username, password, url, provider_type = nil)
      # Create a temporary connection object for testing
      temp_connection = build_temp_connection(username, password, url, provider_type)
      
      service = create_service(temp_connection)
      service.test_connection
    end
    
    # Get available CalDAV providers
    def self.available_providers
      [
        {
          id: 'icloud',
          name: 'iCloud Calendar',
          description: 'Apple iCloud Calendar integration',
          requires_url: false,
          setup_instructions: [
            'Go to <a href="https://appleid.apple.com" target="_blank" rel="noopener">appleid.apple.com</a> and sign in',
            'Navigate to "Sign-In and Security" > "App-Specific Passwords"',
            'Generate a new password for "BizBlasts Calendar"',
            'Use your iCloud email and the app-specific password'
          ]
        },
        {
          id: 'nextcloud',
          name: 'Nextcloud Calendar',
          description: 'Nextcloud/ownCloud Calendar integration',
          requires_url: true,
          url_placeholder: 'https://your-nextcloud.com',
          setup_instructions: [
            'Use your Nextcloud username and password',
            'If two-factor authentication is enabled, generate an app password',
            'Provide your Nextcloud server URL'
          ]
        },
        {
          id: 'generic',
          name: 'Other CalDAV Server',
          description: 'Generic CalDAV server (FastMail, Yahoo, etc.)',
          requires_url: true,
          url_placeholder: 'https://caldav.server.com/path/to/calendar/',
          setup_instructions: [
            'Obtain your CalDAV server URL from your provider',
            'Use your email/username and password',
            'Some providers may require app-specific passwords'
          ]
        }
      ]
    end
    
    # Get provider information by ID
    def self.provider_info(provider_id)
      available_providers.find { |p| p[:id] == provider_id.to_s }
    end
    
    private

    # Helper method to safely check if a URL's host matches an expected host
    # This prevents URL substring injection attacks like https://evil.com/caldav.icloud.com
    def self.url_host_matches?(url, expected_host)
      return false if url.blank?

      begin
        # Parse the URL to extract the actual host component
        uri = URI.parse(url.to_s)
        # Compare the actual host (case-insensitive) with expected
        uri.host&.downcase == expected_host.downcase
      rescue URI::InvalidURIError
        # Invalid URLs should not match
        false
      end
    end

    # Helper method to check if URL path contains a specific string
    # This is safer than checking the entire URL string
    def self.url_path_contains?(url, path_substring)
      return false if url.blank?

      begin
        uri = URI.parse(url.to_s)
        uri.path&.downcase&.include?(path_substring.downcase) || false
      rescue URI::InvalidURIError
        false
      end
    end

    # Helper method to check if URL host contains a substring
    # Used for detecting Nextcloud/ownCloud which can be on any domain
    def self.url_host_contains?(url, host_substring)
      return false if url.blank?

      begin
        uri = URI.parse(url.to_s)
        uri.host&.downcase&.include?(host_substring.downcase) || false
      rescue URI::InvalidURIError
        false
      end
    end

    def self.detect_provider(calendar_connection)
      # First check explicit provider setting
      if calendar_connection.caldav_provider.present?
        return calendar_connection.caldav_provider.to_sym
      end

      # Auto-detect based on username/email and URL
      username = calendar_connection.caldav_username&.downcase
      url = calendar_connection.caldav_url

      # iCloud detection
      # Check username domain or exact URL host match
      if username&.include?('@icloud.com') ||
         username&.include?('@me.com') ||
         username&.include?('@mac.com') ||
         url_host_matches?(url, 'caldav.icloud.com')
        return :icloud
      end

      # Nextcloud detection
      # Check if host contains 'nextcloud'/'owncloud' or path contains specific pattern
      if url_host_contains?(url, 'nextcloud') ||
         url_host_contains?(url, 'owncloud') ||
         url_path_contains?(url, 'remote.php/dav')
        return :nextcloud
      end

      # Default to generic
      :generic
    end
    
    def self.build_temp_connection(username, password, url, provider_type)
      # Create a temporary connection object for testing
      # This doesn't save to database
      CalendarConnection.new(
        provider: :caldav,
        caldav_username: username,
        caldav_password: password,
        caldav_url: url,
        caldav_provider: provider_type,
        active: false # Don't activate until test passes
      )
    end
  end
end