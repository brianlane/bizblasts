# frozen_string_literal: true

module EmailMarketing
  # Job for processing incoming webhooks from email marketing platforms
  class ProcessWebhookJob < ApplicationJob
    queue_as :email_marketing

    # @param provider [String] 'mailchimp' or 'constant_contact'
    # @param connection_id [Integer] The EmailMarketingConnection ID
    # @param webhook_data [Hash] The webhook payload data
    def perform(provider, connection_id, webhook_data)
      connection = EmailMarketingConnection.find_by(id: connection_id)
      return unless connection&.active?

      Rails.logger.info "[EmailMarketing::ProcessWebhookJob] Processing #{provider} webhook for connection #{connection_id}"

      ActsAsTenant.with_tenant(connection.business) do
        sync_service = connection.sync_service
        sync_service.handle_webhook(webhook_data.with_indifferent_access)
      end
    rescue StandardError => e
      Rails.logger.error "[EmailMarketing::ProcessWebhookJob] Error processing webhook: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
    end
  end
end
