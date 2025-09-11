# frozen_string_literal: true

# Background job for custom domain setup to prevent 502 crashes during user requests
# This job is triggered when a business switches from subdomain to custom domain
class CustomDomainSetupJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff for transient failures
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(business_id)
    business = Business.find(business_id)
    
    Rails.logger.info "[CustomDomainSetupJob] Starting domain setup for business #{business_id} (#{business.hostname})"
    
    # Run the domain setup service
    result = CnameSetupService.new(business).start_setup!
    
    if result[:success]
      Rails.logger.info "[CustomDomainSetupJob] Domain setup completed successfully for business #{business_id}"
    else
      Rails.logger.error "[CustomDomainSetupJob] Domain setup failed for business #{business_id}: #{result[:error]}"
    end
    
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[CustomDomainSetupJob] Business #{business_id} not found: #{e.message}"
  rescue => e
    Rails.logger.error "[CustomDomainSetupJob] Unexpected error for business #{business_id}: #{e.message}"
    raise # Re-raise to trigger retry logic
  end
end
