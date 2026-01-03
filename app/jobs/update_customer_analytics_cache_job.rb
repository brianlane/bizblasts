# frozen_string_literal: true

# Background job to update cached analytics fields for a customer
# Triggered when payments are created/updated to keep analytics performant
class UpdateCustomerAnalyticsCacheJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff if there are temporary database issues
  retry_on ActiveRecord::Deadlocked, wait: :exponentially_longer, attempts: 3
  retry_on ActiveRecord::LockWaitTimeout, wait: :exponentially_longer, attempts: 3

  def perform(tenant_customer_id)
    customer = TenantCustomer.find_by(id: tenant_customer_id)
    return unless customer

    # Update all cached analytics fields
    customer.update_cached_analytics_fields!

    Rails.logger.info "[UpdateCustomerAnalyticsCache] Updated cached analytics for customer #{customer.id}"
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[UpdateCustomerAnalyticsCache] Customer #{tenant_customer_id} not found, skipping cache update"
  rescue StandardError => e
    Rails.logger.error "[UpdateCustomerAnalyticsCache] Failed to update analytics cache for customer #{tenant_customer_id}: #{e.message}"
    raise # Re-raise to trigger retry logic
  end
end
