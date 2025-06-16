# frozen_string_literal: true

class ProcessSubscriptionsJob < ApplicationJob
  queue_as :default
  
  def perform(date = Date.current)
    Rails.logger.info "[SUBSCRIPTION JOB] Processing subscriptions for #{date}"
    
    subscriptions_to_process = CustomerSubscription.due_for_billing.includes(
      :business, :tenant_customer, :product, :service, :preferred_staff_member
    )
    
    Rails.logger.info "[SUBSCRIPTION JOB] Found #{subscriptions_to_process.count} subscriptions to process"
    
    processed_count = 0
    failed_count = 0
    
    subscriptions_to_process.find_each do |subscription|
      begin
        ActsAsTenant.with_tenant(subscription.business) do
          result = subscription.process_billing!
          
          if result
            processed_count += 1
            Rails.logger.info "[SUBSCRIPTION JOB] Successfully processed subscription #{subscription.id}"
          else
            failed_count += 1
            Rails.logger.warn "[SUBSCRIPTION JOB] Failed to process subscription #{subscription.id}"
          end
        end
      rescue => e
        failed_count += 1
        Rails.logger.error "[SUBSCRIPTION JOB] Error processing subscription #{subscription.id}: #{e.message}"
        
        # Record the failure
        subscription.subscription_transactions.create!(
          business: subscription.business,
          tenant_customer: subscription.tenant_customer,
          transaction_type: :failed_payment,
          status: :failed,
          processed_date: date,
          failure_reason: e.message,
          notes: "Job processing error: #{e.message}"
        )
        
        # Send failure notifications
        begin
          SubscriptionMailer.payment_failed(subscription).deliver_now
        rescue => mail_error
          Rails.logger.error "[SUBSCRIPTION JOB] Failed to send payment failure email: #{mail_error.message}"
        end
      end
    end
    
    Rails.logger.info "[SUBSCRIPTION JOB] Processing complete. Processed: #{processed_count}, Failed: #{failed_count}"
    
    # Schedule retry job for failed subscriptions in 1 hour
    if failed_count > 0
      RetryFailedSubscriptionsJob.set(wait: 1.hour).perform_later(date)
    end
  end
end 
 
 
 
 