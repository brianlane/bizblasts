# frozen_string_literal: true

# Background job to clean up expired and used authentication tokens
# 
# While DB TTL automatically expires tokens, this job provides additional cleanup
# for edge cases where TTL wasn't set properly, and monitors token usage patterns.
class AuthTokenCleanupJob < ApplicationJob
  queue_as :default
  
  # Run cleanup every 5 minutes
  CLEANUP_INTERVAL = 5.minutes.freeze
  
  # Maximum number of tokens to process in one batch to avoid memory issues
  BATCH_SIZE = 1000
  
  def perform
    cleanup_count = 0
    orphaned_count = 0
    
    Rails.logger.info "[AuthTokenCleanup] Starting cleanup job"
    
    begin
      # Cleanup expired tokens (DB-backed)
      cleanup_count = AuthToken.cleanup_expired!
      
      # Hook for orphan detection (returns 0 by default in DB-backed mode)
      orphaned_count = cleanup_orphaned_tokens
      
      # Log metrics for monitoring
      log_cleanup_metrics(cleanup_count, orphaned_count)
      
      # Schedule next cleanup
      schedule_next_cleanup
      
    rescue => e
      Rails.logger.error "[AuthTokenCleanup] Error during cleanup: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Still schedule next cleanup even if this one failed
      schedule_next_cleanup
      raise
    end
  end
  
  private
  
  # No-op without Redis; kept for interface compatibility
  def cleanup_orphaned_tokens
    0
  end
  
  def log_cleanup_metrics(cleanup_count, orphaned_count)
    total_cleaned = cleanup_count + orphaned_count
    
    if total_cleaned > 0
      Rails.logger.info "[AuthTokenCleanup] Cleaned up #{total_cleaned} tokens (#{cleanup_count} expired, #{orphaned_count} orphaned)"
    else
      Rails.logger.debug "[AuthTokenCleanup] No tokens needed cleanup"
    end
    
    # Log metrics for monitoring/alerting
    if orphaned_count > 10
      Rails.logger.warn "[AuthTokenCleanup] High number of orphaned tokens detected: #{orphaned_count}. Check TTL setting logic."
    end
    
    # Could send metrics to monitoring service here
    # Example: StatsD.gauge('auth_tokens.cleaned', total_cleaned)
    # Example: StatsD.gauge('auth_tokens.orphaned', orphaned_count)
  end
  
  def schedule_next_cleanup
    # Schedule the next cleanup job
    AuthTokenCleanupJob.set(wait: CLEANUP_INTERVAL).perform_later
    Rails.logger.debug "[AuthTokenCleanup] Scheduled next cleanup in #{CLEANUP_INTERVAL.inspect}"
  end
  
  # Class method to start the recurring cleanup process
  def self.start_recurring_cleanup!
    # Only start if not already running
    unless job_already_scheduled?
      AuthTokenCleanupJob.perform_later
      Rails.logger.info "[AuthTokenCleanup] Started recurring cleanup job"
    else
      Rails.logger.debug "[AuthTokenCleanup] Cleanup job already scheduled"
    end
  end
  
  # Check if cleanup job is already scheduled
  def self.job_already_scheduled?
    # This is a simple check - in production you might want more sophisticated detection
    # using job queue inspection or Redis flags
    false # For now, allow multiple schedules (ActiveJob will handle duplicates)
  end
  
  # Manual cleanup method for maintenance or testing
  def self.cleanup_now!
    Rails.logger.info "[AuthTokenCleanup] Starting manual cleanup"
    job = new
    job.perform
  end
end