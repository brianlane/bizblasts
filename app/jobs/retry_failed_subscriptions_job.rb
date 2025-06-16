# frozen_string_literal: true

class RetryFailedSubscriptionsJob < ApplicationJob
  queue_as :default
  
  def perform(date = Date.current)
    Rails.logger.info "[SUBSCRIPTION RETRY JOB] Retrying failed subscriptions for #{date}"
    
    # Find subscriptions that failed and are eligible for retry
    failed_transactions = SubscriptionTransaction.pending_retry.includes(
      :customer_subscription, :business, :tenant_customer
    )
    
    Rails.logger.info "[SUBSCRIPTION RETRY JOB] Found #{failed_transactions.count} failed transactions to retry"
    
    retried_count = 0
    permanently_failed_count = 0
    
    failed_transactions.find_each do |transaction|
      subscription = transaction.customer_subscription
      
      begin
        ActsAsTenant.with_tenant(subscription.business) do
          # Only retry if subscription is still active
          next unless subscription.active?
          
          # Check if max retries exceeded before attempting retry
          if transaction.retry_count >= 3
            subscription.update!(status: :failed, failure_reason: "Maximum retry attempts exceeded")
            transaction.update!(status: :failed, failure_reason: "Maximum retry attempts exceeded")
            permanently_failed_count += 1
            Rails.logger.warn "[SUBSCRIPTION RETRY JOB] Max retries exceeded for subscription #{subscription.id}"
            next
          end
          
          result = subscription.process_billing!
          
          if result
            transaction.mark_completed!("Retry successful")
            retried_count += 1
            Rails.logger.info "[SUBSCRIPTION RETRY JOB] Successfully retried subscription #{subscription.id}"
          else
            transaction.schedule_retry!
            Rails.logger.warn "[SUBSCRIPTION RETRY JOB] Retry failed for subscription #{subscription.id}"
          end
        end
      rescue => e
        Rails.logger.error "[SUBSCRIPTION RETRY JOB] Error retrying subscription #{subscription.id}: #{e.message}"
        
        if transaction.retry_count >= 3
          # Mark as permanently failed
          subscription.update!(status: :failed)
          transaction.update!(status: :failed, failure_reason: "Max retries exceeded: #{e.message}")
          permanently_failed_count += 1
          
          # Notify business and customer of permanent failure
          SubscriptionMailer.permanent_failure(subscription).deliver_later
        else
          transaction.schedule_retry!
        end
      end
    end
    
    Rails.logger.info "[SUBSCRIPTION RETRY JOB] Retry complete. Successful: #{retried_count}, Permanently failed: #{permanently_failed_count}"
  end
end 
 
 
 
 