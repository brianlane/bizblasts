# frozen_string_literal: true

require 'base64'

module EmailMarketing
  module Mailchimp
    # Handles Mailchimp OAuth2 authentication flow
    class OauthHandler < BaseOauthHandler
      PROVIDER = 'mailchimp'

      def authorization_url(business_id, redirect_uri)
        unless MailchimpOauthCredentials.configured?
          add_error(:missing_credentials, 'Mailchimp OAuth credentials not configured')
          return nil
        end

        state = generate_state(business_id, PROVIDER)

        params = {
          response_type: 'code',
          client_id: MailchimpOauthCredentials.client_id,
          redirect_uri: redirect_uri,
          state: state
        }

        "#{MailchimpOauthCredentials.authorize_url}?#{URI.encode_www_form(params)}"
      end

      def handle_callback(code:, state:, redirect_uri:)
        state_data = verify_state(state)
        return nil unless state_data

        unless MailchimpOauthCredentials.configured?
          add_error(:missing_credentials, 'Mailchimp OAuth credentials not configured')
          return nil
        end

        # Exchange code for token
        token_data = exchange_code_for_token(code: code, redirect_uri: redirect_uri)
        return nil unless token_data

        # Get account metadata (datacenter and account info)
        metadata = get_account_metadata(token_data['access_token'])
        return nil unless metadata

        business = Business.find(state_data['business_id'])

        ActsAsTenant.with_tenant(business) do
          connection = business.email_marketing_connections.find_or_initialize_by(provider: :mailchimp)
          connection.assign_attributes(
            access_token: token_data['access_token'],
            # Mailchimp access tokens don't expire but can be revoked
            token_expires_at: nil,
            account_id: metadata['accountname'] || metadata['login']['login_id'],
            account_email: metadata['login']['email'],
            api_server: metadata['dc'],
            active: true,
            connected_at: connection.connected_at || Time.current
          )

          if connection.save
            Rails.logger.info "[Mailchimp::OauthHandler] Connected business #{business.id} to Mailchimp account: #{connection.account_email}"
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
        # Mailchimp access tokens don't expire, so no refresh needed
        # However, we should verify the token is still valid
        return true unless connection.token_expired?

        true
      end

      private

      def exchange_code_for_token(code:, redirect_uri:)
        body = {
          grant_type: 'authorization_code',
          code: code,
          redirect_uri: redirect_uri,
          client_id: MailchimpOauthCredentials.client_id,
          client_secret: MailchimpOauthCredentials.client_secret
        }

        status, response = http_post(
          MailchimpOauthCredentials.token_url,
          body,
          { 'Content-Type' => 'application/x-www-form-urlencoded' }
        )

        if status != 200
          error_msg = response['error_description'] || response['error'] || 'Token exchange failed'
          add_error(:authorization_failed, "Mailchimp token exchange failed: #{error_msg}")
          return nil
        end

        response
      end

      def get_account_metadata(access_token)
        status, response = http_get(
          MailchimpOauthCredentials.metadata_url,
          { 'Authorization' => "OAuth #{access_token}" }
        )

        if status != 200
          error_msg = response['error'] || response['detail'] || 'Failed to get account metadata'
          add_error(:metadata_failed, "Failed to get Mailchimp account info: #{error_msg}")
          return nil
        end

        response
      end
    end
  end
end
