class SmsNotificationReplayJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff for transient failures
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # Don't retry for permanent failures
  discard_on ArgumentError, ActiveRecord::RecordNotFound

  def perform(customer_id, business_id = nil, retry_count = 0)
    Rails.logger.info "[SMS_REPLAY_JOB] Starting job for customer #{customer_id}, business #{business_id || 'all'}, retry #{retry_count}"

    customer = TenantCustomer.find(customer_id)
    business = business_id ? Business.find(business_id) : nil

    # Verify customer can receive SMS before processing
    unless customer.phone_opt_in?
      Rails.logger.warn "[SMS_REPLAY_JOB] Customer #{customer_id} is not opted in for SMS, skipping replay"
      return
    end

    # If business-specific, verify customer can receive SMS from that business
    if business && customer.opted_out_from_business?(business)
      Rails.logger.warn "[SMS_REPLAY_JOB] Customer #{customer_id} is opted out from business #{business_id}, skipping replay"
      return
    end

    # Process the pending notifications
    results = SmsNotificationReplayService.replay_for_customer(customer, business)

    # Log results for monitoring
    Rails.logger.info "[SMS_REPLAY_JOB] Completed for customer #{customer_id}: #{results}"

    # If there are rate-limited notifications, schedule a retry job with delay
    if results[:rate_limited] > 0
      # Prevent infinite loops - max 5 retries
      if retry_count >= 5
        Rails.logger.error "[SMS_REPLAY_JOB] Max retries (#{retry_count}) reached for customer #{customer_id}, abandoning #{results[:rate_limited]} rate-limited notifications"
        # Mark abandoned notifications as failed to prevent future retries
        mark_abandoned_notifications_as_failed(customer, business)
        return results
      end

      # Calculate retry delay based on attempt number
      delay = calculate_retry_delay(retry_count)
      Rails.logger.info "[SMS_REPLAY_JOB] Scheduling retry #{retry_count + 1} for #{results[:rate_limited]} rate-limited notifications in #{delay}"

      self.class.set(wait: delay).perform_later(customer_id, business_id, retry_count + 1)
    end

    results
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[SMS_REPLAY_JOB] Record not found: #{e.message}"
    raise # This will be discarded due to discard_on above
  rescue => e
    Rails.logger.error "[SMS_REPLAY_JOB] Error processing customer #{customer_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise # This will be retried due to retry_on above
  end

  # Class method to schedule replay for a customer
  def self.schedule_for_customer(customer, business = nil)
    perform_later(customer.id, business&.id, 0) # Start with retry_count = 0
    Rails.logger.info "[SMS_REPLAY_JOB] Scheduled replay for customer #{customer.id}, business #{business&.id || 'all'}"
  end

  # Class method to schedule replay with delay (useful for rate limiting)
  def self.schedule_for_customer_delayed(customer, business = nil, delay: 1.hour)
    set(wait: delay).perform_later(customer.id, business&.id, 0) # Start with retry_count = 0
    Rails.logger.info "[SMS_REPLAY_JOB] Scheduled delayed replay (#{delay}) for customer #{customer.id}, business #{business&.id || 'all'}"
  end

  private

  # Calculate exponential backoff delay for rate-limited retries
  def calculate_retry_delay(retry_count)
    case retry_count
    when 0
      15.minutes  # First retry: 15 minutes (might be temporary burst)
    when 1
      1.hour      # Second retry: 1 hour (likely hourly rate limit)
    when 2
      4.hours     # Third retry: 4 hours (might be daily limit partially reset)
    when 3
      12.hours    # Fourth retry: 12 hours (daily limit should reset soon)
    else
      24.hours    # Final retry: 24 hours (full daily reset)
    end
  end

  # Mark rate-limited notifications as failed when max retries reached
  def mark_abandoned_notifications_as_failed(customer, business)
    scope = if business
      PendingSmsNotification.pending.for_customer(customer).for_business(business)
    else
      PendingSmsNotification.pending.for_customer(customer)
    end

    abandoned_count = scope.count
    if abandoned_count > 0
      scope.find_each do |notification|
        notification.mark_as_failed!("Abandoned after max retries due to persistent rate limiting")
      end
      Rails.logger.warn "[SMS_REPLAY_JOB] Marked #{abandoned_count} notifications as failed for customer #{customer.id} due to max retries"
    end
  end
end