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
    
    def self.detect_provider(calendar_connection)
      # First check explicit provider setting
      if calendar_connection.caldav_provider.present?
        return calendar_connection.caldav_provider.to_sym
      end
      
      # Auto-detect based on username/email and URL
      username = calendar_connection.caldav_username&.downcase
      url = calendar_connection.caldav_url&.downcase
      
      # iCloud detection
      if username&.include?('@icloud.com') || 
         username&.include?('@me.com') || 
         username&.include?('@mac.com') ||
         url&.include?('caldav.icloud.com')
        return :icloud
      end
      
      # Nextcloud detection
      if url&.include?('nextcloud') || 
         url&.include?('owncloud') ||
         url&.include?('remote.php/dav')
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