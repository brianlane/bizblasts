# frozen_string_literal: true

module EmailMarketing
  # Job for refreshing OAuth tokens before they expire
  class TokenRefreshJob < ApplicationJob
    queue_as :email_marketing

    # Run this job periodically (e.g., every hour via cron/whenever)
    def perform
      # Find connections with tokens expiring soon
      EmailMarketingConnection.active.needing_refresh.find_each do |connection|
        refresh_connection_token(connection)
      end
    end

    private

    def refresh_connection_token(connection)
      ActsAsTenant.with_tenant(connection.business) do
        oauth_handler = case connection.provider
                        when 'mailchimp'
                          EmailMarketing::Mailchimp::OauthHandler.new
                        when 'constant_contact'
                          EmailMarketing::ConstantContact::OauthHandler.new
                        end

        if oauth_handler.refresh_token(connection)
          Rails.logger.info "[EmailMarketing::TokenRefreshJob] Refreshed token for connection #{connection.id} (#{connection.provider_name})"
        else
          Rails.logger.error "[EmailMarketing::TokenRefreshJob] Failed to refresh token for connection #{connection.id}: #{oauth_handler.errors.full_messages.join(', ')}"
          # Deactivate the connection if token refresh fails
          connection.deactivate!(reason: 'Token refresh failed')
        end
      end
    rescue StandardError => e
      Rails.logger.error "[EmailMarketing::TokenRefreshJob] Error refreshing token for connection #{connection.id}: #{e.message}"
    end
  end
end
