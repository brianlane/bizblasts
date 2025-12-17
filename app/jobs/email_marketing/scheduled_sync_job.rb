# frozen_string_literal: true

module EmailMarketing
  # Job for running scheduled syncs across all businesses
  # This should be run via cron/whenever (e.g., daily at 2 AM)
  class ScheduledSyncJob < ApplicationJob
    queue_as :email_marketing

    def perform
      Rails.logger.info "[EmailMarketing::ScheduledSyncJob] Starting scheduled sync for all connections"

      EmailMarketingConnection.active.sync_strategy_scheduled.find_each do |connection|
        # Queue individual sync jobs to spread the load
        EmailMarketing::SyncContactsJob.perform_later(
          connection.id,
          { sync_type: 'incremental' }
        )
      end

      Rails.logger.info "[EmailMarketing::ScheduledSyncJob] Queued sync jobs for scheduled connections"
    end
  end
end
