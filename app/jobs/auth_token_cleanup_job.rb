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
    # Prevent overlapping runs across processes/threads
    lock_key   = 'auth_token_cleanup:lock'
    owner_token = "#{Process.pid}-#{Thread.current.object_id}-#{SecureRandom.hex(8)}"
    # Acquire lock for the full interval to avoid expiry while job is running.
    got_lock = Rails.cache.write(lock_key, owner_token, unless_exist: true, expires_in: CLEANUP_INTERVAL)
    unless got_lock
      Rails.logger.debug "[AuthTokenCleanup] Another cleanup is running; skipping"
      schedule_next_cleanup
      return
    end

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
    ensure
      # Release the lock only if we still own it
      Rails.cache.delete(lock_key) if Rails.cache.read(lock_key) == owner_token
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
    # In test, always enqueue to keep specs deterministic
    if Rails.env.test?
      AuthTokenCleanupJob.set(wait: CLEANUP_INTERVAL).perform_later
      Rails.logger.debug "[AuthTokenCleanup] (test) Scheduled next cleanup in #{CLEANUP_INTERVAL.inspect}"
      return
    end

    # Use cache key to ensure only one next run is scheduled across processes
    key = 'auth_token_cleanup:next_scheduled'
    if Rails.cache.write(key, Time.current, unless_exist: true, expires_in: CLEANUP_INTERVAL)
      AuthTokenCleanupJob.set(wait: CLEANUP_INTERVAL).perform_later
      Rails.logger.debug "[AuthTokenCleanup] Scheduled next cleanup in #{CLEANUP_INTERVAL.inspect}"
    else
      Rails.logger.debug "[AuthTokenCleanup] Next cleanup already scheduled"
    end
  end
  
  # Class method to start the recurring cleanup process
  def self.start_recurring_cleanup!
    # In test, always enqueue to keep specs deterministic
    if Rails.env.test?
      AuthTokenCleanupJob.perform_later
      Rails.logger.info "[AuthTokenCleanup] Started recurring cleanup job"
      return
    end

    # Guard with cache so only one process schedules the initial job
    key = 'auth_token_cleanup:next_scheduled'
    if Rails.cache.write(key, Time.current, unless_exist: true, expires_in: CLEANUP_INTERVAL)
      AuthTokenCleanupJob.perform_later
      Rails.logger.info "[AuthTokenCleanup] Started recurring cleanup job"
    else
      Rails.logger.debug "[AuthTokenCleanup] Cleanup job already scheduled (cache guard)"
    end
  end
  
  # Check if cleanup job is already scheduled
  def self.job_already_scheduled?
    # Deprecated by cache-based guard; retained for interface compatibility
    false
  end
  
  # Manual cleanup method for maintenance or testing
  def self.cleanup_now!
    Rails.logger.info "[AuthTokenCleanup] Starting manual cleanup"
    job = new
    job.perform
  end
end