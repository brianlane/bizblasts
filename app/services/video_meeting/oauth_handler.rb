# frozen_string_literal: true

module VideoMeeting
  class OauthHandler
    include ActiveModel::Validations

    attr_reader :errors

    def initialize
      @errors = ActiveModel::Errors.new(self)
    end

    # Generate OAuth authorization URL for a provider
    def authorization_url(provider, business_id, staff_member_id, redirect_uri)
      case provider.to_s
      when 'zoom'
        zoom_authorization_url(business_id, staff_member_id, redirect_uri)
      when 'google_meet'
        google_meet_authorization_url(business_id, staff_member_id, redirect_uri)
      else
        add_error(:unsupported_provider, "Unsupported provider: #{provider}")
        nil
      end
    end

    # Handle OAuth callback and create video meeting connection
    def handle_callback(provider, code, state, redirect_uri)
      # Verify state parameter
      state_data = verify_state(state)
      return nil unless state_data

      case provider.to_s
      when 'zoom'
        handle_zoom_callback(code, state_data, redirect_uri)
      when 'google_meet'
        handle_google_meet_callback(code, state_data, redirect_uri)
      else
        add_error(:unsupported_provider, "Unsupported provider: #{provider}")
        nil
      end
    end

    # Refresh an expired access token
    def refresh_token(video_meeting_connection)
      case video_meeting_connection.provider
      when 'zoom'
        refresh_zoom_token(video_meeting_connection)
      when 'google_meet'
        refresh_google_meet_token(video_meeting_connection)
      else
        add_error(:unsupported_provider, "Unsupported provider: #{video_meeting_connection.provider}")
        false
      end
    end

    private

    # ============================================================================
    # Zoom OAuth
    # ============================================================================

    def zoom_authorization_url(business_id, staff_member_id, redirect_uri)
      client_id = zoom_client_id
      unless client_id.present?
        add_error(:missing_credentials, "Zoom OAuth client ID not configured")
        return nil
      end

      state = generate_state(business_id, staff_member_id, 'zoom')

      params = {
        client_id: client_id,
        redirect_uri: redirect_uri,
        response_type: 'code',
        state: state
      }

      "https://zoom.us/oauth/authorize?" + URI.encode_www_form(params)
    end

    def handle_zoom_callback(code, state_data, redirect_uri)
      client_id = zoom_client_id
      client_secret = zoom_client_secret

      unless client_id.present? && client_secret.present?
        add_error(:missing_credentials, "Zoom OAuth credentials not configured")
        return nil
      end

      # Exchange code for tokens
      uri = URI.parse('https://zoom.us/oauth/token')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.path)
      request['Authorization'] = "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}"
      request['Content-Type'] = 'application/x-www-form-urlencoded'
      request.body = URI.encode_www_form({
        grant_type: 'authorization_code',
        code: code,
        redirect_uri: redirect_uri
      })

      begin
        response = http.request(request)
        token_data = JSON.parse(response.body)

        if response.code != '200'
          add_error(:authorization_failed, "Zoom authorization failed: #{token_data['reason'] || token_data['error']}")
          return nil
        end
      rescue => e
        add_error(:authorization_failed, "Zoom authorization failed: #{e.message}")
        return nil
      end

      # Get user info to store UID
      begin
        user_uri = URI.parse('https://api.zoom.us/v2/users/me')
        user_http = Net::HTTP.new(user_uri.host, user_uri.port)
        user_http.use_ssl = true

        user_request = Net::HTTP::Get.new(user_uri.path)
        user_request['Authorization'] = "Bearer #{token_data['access_token']}"

        user_response = user_http.request(user_request)
        user_data = JSON.parse(user_response.body)
        uid = user_data['id']
      rescue => e
        add_error(:api_error, "Failed to get Zoom user info: #{e.message}")
        return nil
      end

      create_video_meeting_connection(
        provider: 'zoom',
        business_id: state_data['business_id'],
        staff_member_id: state_data['staff_member_id'],
        uid: uid,
        access_token: token_data['access_token'],
        refresh_token: token_data['refresh_token'],
        token_expires_at: Time.current + token_data['expires_in'].to_i.seconds,
        scopes: token_data['scope']
      )
    end

    def refresh_zoom_token(connection)
      client_id = zoom_client_id
      client_secret = zoom_client_secret

      uri = URI.parse('https://zoom.us/oauth/token')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.path)
      request['Authorization'] = "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}"
      request['Content-Type'] = 'application/x-www-form-urlencoded'
      request.body = URI.encode_www_form({
        grant_type: 'refresh_token',
        refresh_token: connection.refresh_token
      })

      begin
        response = http.request(request)
        token_data = JSON.parse(response.body)

        if response.code != '200'
          add_error(:refresh_failed, "Failed to refresh Zoom token: #{token_data['reason'] || token_data['error']}")
          connection.deactivate!
          return false
        end

        connection.update!(
          access_token: token_data['access_token'],
          refresh_token: token_data['refresh_token'],
          token_expires_at: Time.current + token_data['expires_in'].to_i.seconds
        )

        true
      rescue => e
        add_error(:refresh_failed, "Failed to refresh Zoom token: #{e.message}")
        connection.deactivate!
        false
      end
    end

    # ============================================================================
    # Google Meet OAuth
    # ============================================================================

    def google_meet_authorization_url(business_id, staff_member_id, redirect_uri)
      require 'googleauth'

      state = generate_state(business_id, staff_member_id, 'google_meet')

      client_id = GoogleOauthCredentials.client_id

      unless GoogleOauthCredentials.configured?
        add_error(:missing_credentials, "Google OAuth credentials not configured")
        return nil
      end

      params = {
        client_id: client_id,
        redirect_uri: redirect_uri,
        # Need calendar.events scope to create calendar events with Meet links
        scope: 'https://www.googleapis.com/auth/calendar.events',
        response_type: 'code',
        access_type: 'offline',
        prompt: 'consent',
        state: state
      }

      "https://accounts.google.com/o/oauth2/auth?" + URI.encode_www_form(params)
    end

    def handle_google_meet_callback(code, state_data, redirect_uri)
      require 'googleauth'

      credentials = GoogleOauthCredentials.credentials
      client_id = credentials[:client_id]
      client_secret = credentials[:client_secret]

      unless GoogleOauthCredentials.configured?
        add_error(:missing_credentials, "Google OAuth credentials not configured")
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

      # Get user info
      begin
        uri = URI.parse('https://www.googleapis.com/oauth2/v2/userinfo')
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri.path)
        request['Authorization'] = "Bearer #{auth_client.access_token}"

        response = http.request(request)
        user_data = JSON.parse(response.body)
        uid = user_data['id'] || user_data['email']
      rescue => e
        add_error(:api_error, "Failed to get Google user info: #{e.message}")
        return nil
      end

      create_video_meeting_connection(
        provider: 'google_meet',
        business_id: state_data['business_id'],
        staff_member_id: state_data['staff_member_id'],
        uid: uid,
        access_token: auth_client.access_token,
        refresh_token: auth_client.refresh_token,
        token_expires_at: auth_client.expires_at,
        scopes: 'https://www.googleapis.com/auth/calendar.events'
      )
    end

    def refresh_google_meet_token(connection)
      require 'googleauth'

      credentials = GoogleOauthCredentials.credentials

      auth_client = Signet::OAuth2::Client.new(
        client_id: credentials[:client_id],
        client_secret: credentials[:client_secret],
        token_credential_uri: 'https://oauth2.googleapis.com/token',
        refresh_token: connection.refresh_token
      )

      begin
        auth_client.refresh!

        connection.update!(
          access_token: auth_client.access_token,
          token_expires_at: auth_client.expires_at
        )

        true
      rescue Signet::AuthorizationError => e
        add_error(:refresh_failed, "Failed to refresh Google token: #{e.message}")
        connection.deactivate!
        false
      end
    end

    # ============================================================================
    # Helper Methods
    # ============================================================================

    def generate_state(business_id, staff_member_id, provider)
      state_data = {
        business_id: business_id,
        staff_member_id: staff_member_id,
        provider: provider,
        timestamp: Time.current.to_i,
        nonce: SecureRandom.hex(16)
      }

      # Encrypt state data
      Rails.application.message_verifier(:video_meeting_oauth).generate(state_data)
    end

    def verify_state(state)
      return nil if state.blank?

      begin
        state_data = Rails.application.message_verifier(:video_meeting_oauth).verify(state)

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

    def create_video_meeting_connection(attributes)
      business = Business.find(attributes[:business_id])
      staff_member = business.staff_members.find(attributes[:staff_member_id])

      # Set current tenant context
      ActsAsTenant.with_tenant(business) do
        # Remove existing connection for this provider
        existing = staff_member.video_meeting_connections
                                .where(provider: attributes[:provider])
                                .first

        existing&.destroy

        connection = staff_member.video_meeting_connections.build(
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

        if connection.save
          connection
        else
          connection.errors.each do |error|
            add_error(error.attribute, error.message)
          end
          nil
        end
      end
    rescue ActiveRecord::RecordNotFound => e
      add_error(:invalid_ids, "Invalid business or staff member ID")
      nil
    end

    def zoom_client_id
      if Rails.env.development? || Rails.env.test?
        ENV['ZOOM_CLIENT_ID_DEV'] || ENV['ZOOM_CLIENT_ID']
      else
        ENV['ZOOM_CLIENT_ID']
      end
    end

    def zoom_client_secret
      if Rails.env.development? || Rails.env.test?
        ENV['ZOOM_CLIENT_SECRET_DEV'] || ENV['ZOOM_CLIENT_SECRET']
      else
        ENV['ZOOM_CLIENT_SECRET']
      end
    end

    def add_error(type, message)
      @errors.add(type, message)
      Rails.logger.error("[VideoMeeting::OauthHandler] #{type}: #{message}")
    end
  end
end
