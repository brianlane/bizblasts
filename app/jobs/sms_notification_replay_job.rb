class SmsNotificationReplayJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff for transient failures
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # Don't retry for permanent failures
  discard_on ArgumentError, ActiveRecord::RecordNotFound

  def perform(customer_id, business_id = nil)
    Rails.logger.info "[SMS_REPLAY_JOB] Starting job for customer #{customer_id}, business #{business_id || 'all'}"

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

    # If there are rate-limited notifications, schedule a retry job
    if results[:rate_limited] > 0
      Rails.logger.info "[SMS_REPLAY_JOB] Scheduling retry for #{results[:rate_limited]} rate-limited notifications"
      self.class.perform_later(customer_id, business_id)
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
    perform_later(customer.id, business&.id)
    Rails.logger.info "[SMS_REPLAY_JOB] Scheduled replay for customer #{customer.id}, business #{business&.id || 'all'}"
  end

  # Class method to schedule replay with delay (useful for rate limiting)
  def self.schedule_for_customer_delayed(customer, business = nil, delay: 1.hour)
    perform_in(delay, customer.id, business&.id)
    Rails.logger.info "[SMS_REPLAY_JOB] Scheduled delayed replay (#{delay}) for customer #{customer.id}, business #{business&.id || 'all'}"
  end
end