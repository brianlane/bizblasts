# frozen_string_literal: true

# Base job class for all application background jobs
# Provides configuration for retries and error handling
class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
  
  # Retry Resend rate limit errors with exponential backoff
  # Resend allows 2 requests/second, so we'll wait and retry
  retry_on 'Resend::Error::RateLimitExceededError', 
           wait: :exponentially_longer, 
           attempts: 5 do |job, error|
    Rails.logger.warn "[EmailRetry] Retrying job #{job.class.name} due to Resend rate limit: #{error.message}"
  end
  
  # Retry general Resend errors (network issues, temporary API problems)
  retry_on 'Resend::Error', 
           wait: :exponentially_longer, 
           attempts: 3 do |job, error|
    Rails.logger.warn "[EmailRetry] Retrying job #{job.class.name} due to Resend error: #{error.message}"
  end
  
  # Discard jobs for non-existent records after logging
  discard_on ActiveJob::DeserializationError do |job, error|
    Rails.logger.error "[JobDiscard] Discarding job #{job.class.name} due to missing record: #{error.message}"
  end
end
