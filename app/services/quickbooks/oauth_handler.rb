# frozen_string_literal: true

require 'net/http'
require 'base64'
require 'json'

module Quickbooks
  class OauthHandler
    include ActiveModel::Validations

    attr_reader :errors

    AUTHORIZE_URL = 'https://appcenter.intuit.com/connect/oauth2'
    TOKEN_HOST = 'oauth.platform.intuit.com'
    TOKEN_PATH = '/oauth2/v1/tokens/bearer'

    # Minimal scopes for accounting APIs.
    DEFAULT_SCOPE = 'com.intuit.quickbooks.accounting'.freeze

    def initialize
      @errors = ActiveModel::Errors.new(self)
    end

    def authorization_url(business_id, redirect_uri)
      unless QuickbooksOauthCredentials.configured?
        add_error(:missing_credentials, 'QuickBooks OAuth credentials not configured')
        return nil
      end

      state = generate_state(business_id)

      params = {
        client_id: QuickbooksOauthCredentials.client_id,
        scope: DEFAULT_SCOPE,
        response_type: 'code',
        redirect_uri: redirect_uri,
        state: state
      }

      "#{AUTHORIZE_URL}?" + URI.encode_www_form(params)
    end

    def handle_callback(code:, state:, realm_id:, redirect_uri:)
      state_data = verify_state(state)
      return nil unless state_data

      unless QuickbooksOauthCredentials.configured?
        add_error(:missing_credentials, 'QuickBooks OAuth credentials not configured')
        return nil
      end

      if realm_id.blank?
        add_error(:missing_realm_id, 'Missing QuickBooks realmId')
        return nil
      end

      token_data = exchange_code_for_token(code: code, redirect_uri: redirect_uri)
      return nil unless token_data

      business = Business.find(state_data['business_id'])

      ActsAsTenant.with_tenant(business) do
        connection = business.quickbooks_connection || business.build_quickbooks_connection
        connection.assign_attributes(
          realm_id: realm_id,
          access_token: token_data['access_token'],
          refresh_token: token_data['refresh_token'],
          token_expires_at: Time.current + token_data['expires_in'].to_i.seconds,
          refresh_token_expires_at: token_data['x_refresh_token_expires_in'].present? ? Time.current + token_data['x_refresh_token_expires_in'].to_i.seconds : nil,
          scopes: token_data['scope'],
          environment: QuickbooksOauthCredentials.environment,
          active: true,
          connected_at: connection.connected_at || Time.current
        )

        if connection.save
          connection
        else
          connection.errors.each { |err| add_error(err.attribute, err.message) }
          nil
        end
      end
    rescue ActiveRecord::RecordNotFound
      add_error(:invalid_business, 'Invalid business for OAuth state')
      nil
    end

    def refresh_token(connection)
      unless QuickbooksOauthCredentials.configured?
        add_error(:missing_credentials, 'QuickBooks OAuth credentials not configured')
        connection.deactivate!
        return false
      end

      return false if connection.refresh_token.blank?

      connection.with_lock do
        return true unless connection.token_expired?

        token_data = exchange_refresh_token(refresh_token: connection.refresh_token)
        return false unless token_data

        connection.update!(
          access_token: token_data['access_token'],
          refresh_token: token_data['refresh_token'].presence || connection.refresh_token,
          token_expires_at: Time.current + token_data['expires_in'].to_i.seconds,
          refresh_token_expires_at: token_data['x_refresh_token_expires_in'].present? ? Time.current + token_data['x_refresh_token_expires_in'].to_i.seconds : connection.refresh_token_expires_at,
          scopes: token_data['scope'].presence || connection.scopes,
          last_used_at: Time.current
        )

        true
      end
    rescue => e
      add_error(:refresh_failed, "Failed to refresh token: #{e.message}")
      begin
        connection.deactivate!
      rescue
        nil
      end
      false
    end

    private

    def exchange_code_for_token(code:, redirect_uri:)
      form = {
        grant_type: 'authorization_code',
        code: code,
        redirect_uri: redirect_uri
      }

      post_token(form)
    end

    def exchange_refresh_token(refresh_token:)
      form = {
        grant_type: 'refresh_token',
        refresh_token: refresh_token
      }

      post_token(form)
    end

    def post_token(form)
      uri = URI::HTTPS.build(host: TOKEN_HOST, path: TOKEN_PATH)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Basic #{Base64.strict_encode64("#{QuickbooksOauthCredentials.client_id}:#{QuickbooksOauthCredentials.client_secret}")}"
      request['Accept'] = 'application/json'
      request['Content-Type'] = 'application/x-www-form-urlencoded'
      request.body = URI.encode_www_form(form)

      response = http.request(request)
      body = JSON.parse(response.body) rescue {}

      if response.code.to_s != '200'
        add_error(:authorization_failed, "QuickBooks token exchange failed: #{body['error_description'] || body['error'] || response.code}")
        return nil
      end

      body
    rescue => e
      add_error(:authorization_failed, "QuickBooks token exchange failed: #{e.message}")
      nil
    end

    def generate_state(business_id)
      state_data = {
        business_id: business_id,
        timestamp: Time.current.to_i,
        nonce: SecureRandom.hex(16)
      }

      Rails.application.message_verifier(:quickbooks_oauth).generate(state_data)
    end

    def verify_state(state)
      return nil if state.blank?

      begin
        state_data = Rails.application.message_verifier(:quickbooks_oauth).verify(state)

        # 15 minute expiry
        if Time.current.to_i - state_data['timestamp'].to_i > 15.minutes.to_i
          add_error(:expired_state, 'OAuth state expired')
          return nil
        end

        state_data
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        add_error(:invalid_state, 'Invalid OAuth state')
        nil
      rescue => e
        add_error(:invalid_state, "Error validating OAuth state: #{e.message}")
        nil
      end
    end

    def add_error(type, message)
      @errors.add(type, message)
      Rails.logger.error("[Quickbooks::OauthHandler] #{type}: #{message}")
    end
  end
end
