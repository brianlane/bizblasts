# frozen_string_literal: true

module Calendar
  class OauthHandler
    include ActiveModel::Validations
    
    attr_reader :errors
    
    def initialize
      @errors = ActiveModel::Errors.new(self)
    end
    
    # Generate OAuth authorization URL for a provider
    def authorization_url(provider, business_id, staff_member_id, redirect_uri)
      case provider.to_s
      when 'google'
        google_authorization_url(business_id, staff_member_id, redirect_uri)
      when 'microsoft'
        microsoft_authorization_url(business_id, staff_member_id, redirect_uri)
      else
        add_error(:unsupported_provider, "Unsupported provider: #{provider}")
        nil
      end
    end
    
    # Handle OAuth callback and create calendar connection
    def handle_callback(provider, code, state, redirect_uri)
      # Verify state parameter
      state_data = verify_state(state)
      return nil unless state_data
      
      case provider.to_s
      when 'google'
        handle_google_callback(code, state_data, redirect_uri)
      when 'microsoft'
        handle_microsoft_callback(code, state_data, redirect_uri)
      else
        add_error(:unsupported_provider, "Unsupported provider: #{provider}")
        nil
      end
    end
    
    # Refresh an expired access token
    def refresh_token(calendar_connection)
      case calendar_connection.provider
      when 'google'
        refresh_google_token(calendar_connection)
      when 'microsoft'
        refresh_microsoft_token(calendar_connection)
      else
        add_error(:unsupported_provider, "Unsupported provider: #{calendar_connection.provider}")
        false
      end
    end
    
    private
    
    def google_authorization_url(business_id, staff_member_id, redirect_uri)
      require 'googleauth'
      
      state = generate_state(business_id, staff_member_id, 'google')
      
      client_id = ENV['GOOGLE_CALENDAR_CLIENT_ID']
      unless client_id
        add_error(:missing_credentials, "Google Calendar client ID not configured")
        return nil
      end
      
      params = {
        client_id: client_id,
        redirect_uri: redirect_uri,
        scope: 'https://www.googleapis.com/auth/calendar',
        response_type: 'code',
        access_type: 'offline',
        prompt: 'consent',
        state: state
      }
      
      "https://accounts.google.com/o/oauth2/auth?" + URI.encode_www_form(params)
    end
    
    def microsoft_authorization_url(business_id, staff_member_id, redirect_uri)
      state = generate_state(business_id, staff_member_id, 'microsoft')
      
      client_id = ENV['MICROSOFT_CLIENT_ID']
      unless client_id
        add_error(:missing_credentials, "Microsoft Graph client ID not configured")
        return nil
      end
      
      params = {
        client_id: client_id,
        response_type: 'code',
        redirect_uri: redirect_uri,
        scope: 'https://graph.microsoft.com/Calendars.ReadWrite offline_access',
        state: state,
        prompt: 'consent'
      }
      
      "https://login.microsoftonline.com/common/oauth2/v2.0/authorize?" + URI.encode_www_form(params)
    end
    
    def handle_google_callback(code, state_data, redirect_uri)
      require 'googleauth'
      require 'google/apis/calendar_v3'
      
      client_id = ENV['GOOGLE_CALENDAR_CLIENT_ID']
      client_secret = ENV['GOOGLE_CALENDAR_CLIENT_SECRET']
      
      unless client_id && client_secret
        add_error(:missing_credentials, "Google Calendar credentials not configured")
        return nil
      end
      
      # Exchange code for tokens
      auth_client = Signet::OAuth2::Client.new(
        client_id: client_id,
        client_secret: client_secret,
        token_credential_uri: 'https://oauth2.googleapis.com/token',
        redirect_uri: redirect_uri
      )
      
      auth_client.code = code
      
      begin
        auth_client.fetch_access_token!
      rescue Signet::AuthorizationError => e
        add_error(:authorization_failed, "Google authorization failed: #{e.message}")
        return nil
      end
      
      # Get user info to store UID
      calendar_service = Google::Apis::CalendarV3::CalendarService.new
      calendar_service.authorization = auth_client
      
      begin
        calendar_list = calendar_service.list_calendar_lists
        primary_calendar = calendar_list.items.find { |cal| cal.primary }
        uid = primary_calendar&.id || auth_client.id_token&.[]('sub')
      rescue Google::Apis::Error => e
        add_error(:api_error, "Failed to get Google Calendar info: #{e.message}")
        return nil
      end
      
      create_calendar_connection(
        provider: 'google',
        business_id: state_data['business_id'],
        staff_member_id: state_data['staff_member_id'],
        uid: uid,
        access_token: auth_client.access_token,
        refresh_token: auth_client.refresh_token,
        token_expires_at: auth_client.expires_at,
        scopes: 'https://www.googleapis.com/auth/calendar'
      )
    end
    
    def handle_microsoft_callback(code, state_data, redirect_uri)
      client_id = ENV['MICROSOFT_CLIENT_ID']
      client_secret = ENV['MICROSOFT_CLIENT_SECRET']
      
      unless client_id && client_secret
        add_error(:missing_credentials, "Microsoft Graph credentials not configured")
        return nil
      end
      
      # Exchange code for tokens
      oauth_client = OAuth2::Client.new(
        client_id,
        client_secret,
        site: 'https://login.microsoftonline.com',
        authorize_url: '/common/oauth2/v2.0/authorize',
        token_url: '/common/oauth2/v2.0/token'
      )
      
      begin
        access_token = oauth_client.auth_code.get_token(
          code,
          redirect_uri: redirect_uri,
          scope: 'https://graph.microsoft.com/Calendars.ReadWrite offline_access'
        )
      rescue OAuth2::Error => e
        add_error(:authorization_failed, "Microsoft authorization failed: #{e.response.body}")
        return nil
      end
      
      # Get user info
      begin
        response = access_token.get('https://graph.microsoft.com/v1.0/me')
        user_info = JSON.parse(response.body)
        uid = user_info['id']
      rescue OAuth2::Error => e
        add_error(:api_error, "Failed to get Microsoft user info: #{e.message}")
        return nil
      end
      
      create_calendar_connection(
        provider: 'microsoft',
        business_id: state_data['business_id'],
        staff_member_id: state_data['staff_member_id'],
        uid: uid,
        access_token: access_token.token,
        refresh_token: access_token.refresh_token,
        token_expires_at: access_token.expires_at ? Time.at(access_token.expires_at) : nil,
        scopes: 'https://graph.microsoft.com/Calendars.ReadWrite offline_access'
      )
    end
    
    def refresh_google_token(calendar_connection)
      require 'googleauth'
      
      client_id = ENV['GOOGLE_CALENDAR_CLIENT_ID']
      client_secret = ENV['GOOGLE_CALENDAR_CLIENT_SECRET']
      
      auth_client = Signet::OAuth2::Client.new(
        client_id: client_id,
        client_secret: client_secret,
        token_credential_uri: 'https://oauth2.googleapis.com/token',
        refresh_token: calendar_connection.refresh_token
      )
      
      begin
        auth_client.refresh!
        
        calendar_connection.update!(
          access_token: auth_client.access_token,
          token_expires_at: auth_client.expires_at,
          last_synced_at: Time.current
        )
        
        true
      rescue Signet::AuthorizationError => e
        add_error(:refresh_failed, "Failed to refresh Google token: #{e.message}")
        calendar_connection.deactivate!
        false
      end
    end
    
    def refresh_microsoft_token(calendar_connection)
      client_id = ENV['MICROSOFT_CLIENT_ID']
      client_secret = ENV['MICROSOFT_CLIENT_SECRET']
      
      oauth_client = OAuth2::Client.new(
        client_id,
        client_secret,
        site: 'https://login.microsoftonline.com',
        token_url: '/common/oauth2/v2.0/token'
      )
      
      begin
        refresh_token_obj = OAuth2::AccessToken.new(
          oauth_client,
          calendar_connection.access_token,
          refresh_token: calendar_connection.refresh_token
        )
        
        new_token = refresh_token_obj.refresh!
        
        calendar_connection.update!(
          access_token: new_token.token,
          refresh_token: new_token.refresh_token,
          token_expires_at: new_token.expires_at ? Time.at(new_token.expires_at) : nil,
          last_synced_at: Time.current
        )
        
        true
      rescue OAuth2::Error => e
        add_error(:refresh_failed, "Failed to refresh Microsoft token: #{e.message}")
        calendar_connection.deactivate!
        false
      end
    end
    
    def generate_state(business_id, staff_member_id, provider)
      state_data = {
        business_id: business_id,
        staff_member_id: staff_member_id,
        provider: provider,
        timestamp: Time.current.to_i,
        nonce: SecureRandom.hex(16)
      }
      
      # Encrypt state data
      Rails.application.message_verifier(:calendar_oauth).generate(state_data)
    end
    
    def verify_state(state)
      return nil if state.blank?
      
      begin
        state_data = Rails.application.message_verifier(:calendar_oauth).verify(state)
        
        # Check if state is not too old (15 minutes max)
        if Time.current.to_i - state_data['timestamp'] > 15.minutes
          add_error(:expired_state, "OAuth state expired")
          return nil
        end
        
        state_data
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        add_error(:invalid_state, "Invalid OAuth state")
        nil
      end
    end
    
    def create_calendar_connection(attributes)
      business = Business.find(attributes[:business_id])
      staff_member = business.staff_members.find(attributes[:staff_member_id])
      
      # Set current tenant context
      ActsAsTenant.with_tenant(business) do
        # Remove existing connection for this provider
        existing = staff_member.calendar_connections
                                .where(provider: attributes[:provider])
                                .first
        
        if existing
          # Remove default calendar connection reference first
          if staff_member.default_calendar_connection == existing
            staff_member.update(default_calendar_connection: nil)
          end
          existing.destroy
        end
        
        calendar_connection = staff_member.calendar_connections.build(
          business: business,
          provider: attributes[:provider],
          uid: attributes[:uid],
          access_token: attributes[:access_token],
          refresh_token: attributes[:refresh_token],
          token_expires_at: attributes[:token_expires_at],
          scopes: attributes[:scopes],
          connected_at: Time.current,
          active: true
        )
        
        if calendar_connection.save
          # Set as default if this is the first connection
          unless staff_member.default_calendar_connection
            staff_member.update(default_calendar_connection: calendar_connection)
          end
          
          calendar_connection
        else
          calendar_connection.errors.each do |error|
            add_error(error.attribute, error.message)
          end
          nil
        end
      end
    rescue ActiveRecord::RecordNotFound => e
      add_error(:invalid_ids, "Invalid business or staff member ID")
      nil
    end
    
    def add_error(type, message)
      @errors.add(type, message)
      Rails.logger.error("[Calendar::OauthHandler] #{type}: #{message}")
    end
  end
end