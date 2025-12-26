# frozen_string_literal: true

module Analytics
  # Job for cleaning up old analytics data
  # Runs weekly to archive/delete raw data older than retention period
  class CleanupJob < ApplicationJob
    queue_as :analytics

    # Retention periods
    RAW_DATA_RETENTION_DAYS = 90
    DAILY_SNAPSHOT_RETENTION_YEARS = 2
    WEEKLY_SNAPSHOT_RETENTION_YEARS = 5

    def perform
      Rails.logger.info "[AnalyticsCleanup] Starting analytics cleanup..."
      
      cleanup_old_page_views
      cleanup_old_click_events
      cleanup_old_sessions
      cleanup_old_snapshots
      
      Rails.logger.info "[AnalyticsCleanup] Analytics cleanup complete"
    end

    private

    def cleanup_old_page_views
      cutoff_date = RAW_DATA_RETENTION_DAYS.days.ago
      
      deleted = PageView.where('created_at < ?', cutoff_date).delete_all
      
      Rails.logger.info "[AnalyticsCleanup] Deleted #{deleted} page views older than #{cutoff_date.to_date}"
    end

    def cleanup_old_click_events
      cutoff_date = RAW_DATA_RETENTION_DAYS.days.ago
      
      deleted = ClickEvent.where('created_at < ?', cutoff_date).delete_all
      
      Rails.logger.info "[AnalyticsCleanup] Deleted #{deleted} click events older than #{cutoff_date.to_date}"
    end

    def cleanup_old_sessions
      cutoff_date = RAW_DATA_RETENTION_DAYS.days.ago
      
      # Only delete closed sessions
      deleted = VisitorSession
        .where.not(session_end: nil)
        .where('session_start < ?', cutoff_date)
        .delete_all
      
      Rails.logger.info "[AnalyticsCleanup] Deleted #{deleted} visitor sessions older than #{cutoff_date.to_date}"
    end

    def cleanup_old_snapshots
      # Daily snapshots: keep for 2 years
      daily_cutoff = DAILY_SNAPSHOT_RETENTION_YEARS.years.ago.to_date
      daily_deleted = AnalyticsSnapshot
        .daily
        .where('period_start < ?', daily_cutoff)
        .delete_all
      
      Rails.logger.info "[AnalyticsCleanup] Deleted #{daily_deleted} daily snapshots older than #{daily_cutoff}"
      
      # Weekly snapshots: keep for 5 years
      weekly_cutoff = WEEKLY_SNAPSHOT_RETENTION_YEARS.years.ago.to_date
      weekly_deleted = AnalyticsSnapshot
        .weekly
        .where('period_start < ?', weekly_cutoff)
        .delete_all
      
      Rails.logger.info "[AnalyticsCleanup] Deleted #{weekly_deleted} weekly snapshots older than #{weekly_cutoff}"
      
      # Monthly snapshots: keep indefinitely (no cleanup)
    end
  end
end

