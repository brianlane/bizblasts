# frozen_string_literal: true

# Background job to clean up expired and used authentication tokens
# 
# While Redis TTL automatically expires tokens, this job provides additional cleanup
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
      # Cleanup tokens without TTL (failsafe for edge cases)
      cleanup_count = AuthToken.cleanup_expired!
      
      # Clean up any orphaned tokens that Redis TTL missed
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
  
  def cleanup_orphaned_tokens
    orphaned_count = 0
    processed_count = 0
    
    # Scan Redis for auth token keys and check if they should be cleaned up
    begin
      AuthToken.redis.scan_each(match: "#{AuthToken::REDIS_KEY_PREFIX}:*", count: BATCH_SIZE) do |key|
        processed_count += 1
        
        # Check if token is expired or malformed
        ttl = AuthToken.redis.ttl(key)
        
        # TTL of -1 means key exists but has no expiration (should not happen)
        # TTL of -2 means key doesn't exist
        if ttl == -1
          # Key exists but has no TTL - this shouldn't happen, clean it up
          AuthToken.redis.del(key)
          orphaned_count += 1
          Rails.logger.warn "[AuthTokenCleanup] Cleaned up token without TTL: #{key}"
        elsif ttl == -2
          # Key doesn't exist (this is expected for expired tokens)
          next
        end
        
        # Break if we've processed too many tokens in one job
        break if processed_count >= BATCH_SIZE
      end
    rescue => e
      Rails.logger.error "[AuthTokenCleanup] Error scanning Redis keys: #{e.message}"
    end
    
    Rails.logger.info "[AuthTokenCleanup] Processed #{processed_count} token keys, cleaned #{orphaned_count} orphaned tokens"
    orphaned_count
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