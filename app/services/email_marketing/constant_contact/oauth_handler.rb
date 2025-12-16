# frozen_string_literal: true

require 'base64'

module EmailMarketing
  module ConstantContact
    # Handles Constant Contact OAuth2 authentication flow
    class OauthHandler < BaseOauthHandler
      PROVIDER = 'constant_contact'

      def authorization_url(business_id, redirect_uri)
        unless ConstantContactOauthCredentials.configured?
          add_error(:missing_credentials, 'Constant Contact OAuth credentials not configured')
          return nil
        end

        state = generate_state(business_id, PROVIDER)

        params = {
          response_type: 'code',
          client_id: ConstantContactOauthCredentials.client_id,
          redirect_uri: redirect_uri,
          scope: ConstantContactOauthCredentials.scopes,
          state: state
        }

        "#{ConstantContactOauthCredentials.authorize_url}?#{URI.encode_www_form(params)}"
      end

      def handle_callback(code:, state:, redirect_uri:)
        state_data = verify_state(state)
        return nil unless state_data

        unless ConstantContactOauthCredentials.configured?
          add_error(:missing_credentials, 'Constant Contact OAuth credentials not configured')
          return nil
        end

        # Exchange code for token
        token_data = exchange_code_for_token(code: code, redirect_uri: redirect_uri)
        return nil unless token_data

        # Get account info
        account_info = get_account_info(token_data['access_token'])
        return nil unless account_info

        business = Business.find(state_data['business_id'])

        ActsAsTenant.with_tenant(business) do
          connection = business.email_marketing_connections.find_or_initialize_by(provider: :constant_contact)
          connection.assign_attributes(
            access_token: token_data['access_token'],
            refresh_token: token_data['refresh_token'],
            token_expires_at: Time.current + token_data['expires_in'].to_i.seconds,
            account_id: account_info['encoded_account_id'],
            account_email: account_info['email'],
            active: true,
            connected_at: connection.connected_at || Time.current
          )

          if connection.save
            Rails.logger.info "[ConstantContact::OauthHandler] Connected business #{business.id} to Constant Contact account: #{connection.account_email}"
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
        return true unless connection.token_expired? || connection.token_expiring_soon?
        return false if connection.refresh_token.blank?

        connection.with_lock do
          connection.reload
          return true unless connection.token_expired? || connection.token_expiring_soon?

          token_data = exchange_refresh_token(connection.refresh_token)
          return false unless token_data

          connection.update!(
            access_token: token_data['access_token'],
            refresh_token: token_data['refresh_token'].presence || connection.refresh_token,
            token_expires_at: Time.current + token_data['expires_in'].to_i.seconds
          )

          true
        end
      rescue StandardError => e
        add_error(:refresh_failed, "Failed to refresh token: #{e.message}")
        connection.deactivate!(reason: 'Token refresh failed')
        false
      end

      private

      def exchange_code_for_token(code:, redirect_uri:)
        body = {
          grant_type: 'authorization_code',
          code: code,
          redirect_uri: redirect_uri
        }

        auth_header = Base64.strict_encode64("#{ConstantContactOauthCredentials.client_id}:#{ConstantContactOauthCredentials.client_secret}")

        status, response = http_post(
          ConstantContactOauthCredentials.token_url,
          body,
          {
            'Content-Type' => 'application/x-www-form-urlencoded',
            'Authorization' => "Basic #{auth_header}"
          }
        )

        if status != 200
          error_msg = response['error_description'] || response['error'] || 'Token exchange failed'
          add_error(:authorization_failed, "Constant Contact token exchange failed: #{error_msg}")
          return nil
        end

        response
      end

      def exchange_refresh_token(refresh_token)
        body = {
          grant_type: 'refresh_token',
          refresh_token: refresh_token
        }

        auth_header = Base64.strict_encode64("#{ConstantContactOauthCredentials.client_id}:#{ConstantContactOauthCredentials.client_secret}")

        status, response = http_post(
          ConstantContactOauthCredentials.token_url,
          body,
          {
            'Content-Type' => 'application/x-www-form-urlencoded',
            'Authorization' => "Basic #{auth_header}"
          }
        )

        if status != 200
          error_msg = response['error_description'] || response['error'] || 'Token refresh failed'
          add_error(:refresh_failed, "Constant Contact token refresh failed: #{error_msg}")
          return nil
        end

        response
      end

      def get_account_info(access_token)
        status, response = http_get(
          "#{ConstantContactOauthCredentials.api_base_url}/account/summary",
          {
            'Authorization' => "Bearer #{access_token}",
            'Content-Type' => 'application/json'
          }
        )

        if status != 200
          error_msg = response['error_message'] || response['error'] || 'Failed to get account info'
          add_error(:account_info_failed, "Failed to get Constant Contact account info: #{error_msg}")
          return nil
        end

        response
      end
    end
  end
end
