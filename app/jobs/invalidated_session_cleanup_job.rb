# frozen_string_literal: true

# Background job to clean up expired invalidated sessions
# Prevents the invalidated_sessions table from growing indefinitely
class InvalidatedSessionCleanupJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff on failure
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(schedule_next: !Rails.env.test?)
    start_time = Time.current
    Rails.logger.info "[InvalidatedSessionCleanupJob] Starting cleanup"

    begin
      # Clean up expired entries
      expired_count = InvalidatedSession.cleanup_expired!

      duration = Time.current - start_time
      Rails.logger.info "[InvalidatedSessionCleanupJob] Completed in #{duration.round(2)}s, cleaned #{expired_count} expired sessions"

      # Schedule next cleanup (every 6 hours) if requested
      if schedule_next
        InvalidatedSessionCleanupJob.set(wait: 6.hours).perform_later
      end

    rescue => e
      Rails.logger.error "[InvalidatedSessionCleanupJob] Failed: #{e.message}"
      raise e
    end
  end
end
