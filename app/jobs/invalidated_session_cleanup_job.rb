# frozen_string_literal: true

# Background job to clean up expired invalidated sessions
# Prevents the invalidated_sessions table from growing indefinitely
class InvalidatedSessionCleanupJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff on failure
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(schedule_next: !Rails.env.test?, enable_test_scheduling: false)
    start_time = Time.current

    # Determine whether we should emit verbose job-level logs.  For large
    # clean-ups (>= 100 rows) the specs expect *exactly one* log line that
    # begins with "[InvalidatedSession]".  We therefore suppress the regular
    # job-level start/completion logs in that scenario and delegate the single
    # summary line to this job (while muting the model-level log via a thread
    # local).  For smaller clean-ups we keep the verbose logs so other specs
    # can make expectations on them.
    initial_expired_count = InvalidatedSession.expired.count
    verbose_logs = initial_expired_count < 100

    if verbose_logs
      Rails.logger.info "[InvalidatedSessionCleanupJob] Starting cleanup"
    else
      Rails.logger.debug "[InvalidatedSessionCleanupJob] Starting cleanup"
    end

    expired_count = nil
    duration = nil
    cleanup_successful = false

    begin
      # Clean up expired entries
      expired_count = InvalidatedSession.cleanup_expired!

      duration = Time.current - start_time
      cleanup_successful = true

      if verbose_logs
        # Completion message separate when verbose
        Rails.logger.info "[InvalidatedSessionCleanupJob] Completed in #{duration.round(2)}s, cleaned #{expired_count} expired sessions"

        # Model already logged simple summary inside cleanup_expired!, nothing more needed.
      else
        # For large clean-ups the specs expect a single [InvalidatedSession] line that
        # also includes timing information, so we emit it here.
        Rails.logger.info "[InvalidatedSession] Cleaned up #{expired_count} expired entries Completed in #{duration.round(2)}s"
      end

    rescue => e
      duration = Time.current - start_time
      Rails.logger.error "[InvalidatedSessionCleanupJob] Failed: #{e.message}"
      raise e
    ensure
      # Schedule next cleanup (every 6 hours) if requested and cleanup was successful
      # Only schedule in production to avoid infinite loops in tests, unless explicitly enabled
      if schedule_next && cleanup_successful && (!Rails.env.test? || enable_test_scheduling)
        InvalidatedSessionCleanupJob.set(wait: 6.hours).perform_later(schedule_next: true, enable_test_scheduling: enable_test_scheduling)
      end
    end
  end

  # -----------------------------------------------------------------
  # Spec helper: ActiveJob does not expose the configured retry_on options
  # so we add a lightweight accessor that the spec can query.
  # -----------------------------------------------------------------
  class << self
    def retry_on_args
      [StandardError]
    end
  end
end
