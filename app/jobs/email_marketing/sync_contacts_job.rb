# frozen_string_literal: true

module EmailMarketing
  # Job for syncing contacts to email marketing platforms
  class SyncContactsJob < ApplicationJob
    queue_as :email_marketing

    # Retry on common transient errors
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    # @param connection_id [Integer] The EmailMarketingConnection ID
    # @param options [Hash] Options for the sync
    #   - :sync_type [String] 'full' or 'incremental' (default: 'incremental')
    #   - :list_id [String] Optional specific list ID to sync to
    def perform(connection_id, options = {})
      connection = EmailMarketingConnection.find_by(id: connection_id)
      return unless connection&.connected?

      ActsAsTenant.with_tenant(connection.business) do
        sync_service = connection.sync_service

        case options[:sync_type]&.to_s
        when 'full'
          result = sync_service.sync_all(list_id: options[:list_id])
        else
          result = sync_service.sync_incremental(list_id: options[:list_id])
        end

        if result[:success]
          Rails.logger.info "[EmailMarketing::SyncContactsJob] Sync completed for connection #{connection_id}: #{result[:synced]} synced, #{result[:failed]} failed"
        else
          Rails.logger.error "[EmailMarketing::SyncContactsJob] Sync failed for connection #{connection_id}: #{result[:error]}"
        end
      end
    end
  end
end
