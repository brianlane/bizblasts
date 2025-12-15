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
    
    # Re-validate eligibility checks since business state may have changed after queuing
    unless eligible_for_domain_setup?(business)
      Rails.logger.info "[CustomDomainSetupJob] Business #{business_id} no longer eligible for domain setup, skipping"
      return
    end
    
    # Run the domain setup service
    result = CnameSetupService.new(business).start_setup!
    
    # Handle result safely - it should be a hash but may not be
    if result.is_a?(Hash)
      if result[:success]
        Rails.logger.info "[CustomDomainSetupJob] Domain setup completed successfully for business #{business_id}"
      else
        Rails.logger.error "[CustomDomainSetupJob] Domain setup failed for business #{business_id}: #{result[:error]}"
      end
    else
      # If result is not a hash, log it and assume failure
      Rails.logger.error "[CustomDomainSetupJob] Domain setup returned unexpected result for business #{business_id}: #{result.inspect}"
    end
    
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[CustomDomainSetupJob] Business #{business_id} not found: #{e.message}"
  rescue => e
    Rails.logger.error "[CustomDomainSetupJob] Unexpected error for business #{business_id}: #{e.message}"
    raise # Re-raise to trigger retry logic
  end

  private

  # Re-validate all eligibility checks that were in the original callback
  # This ensures business state hasn't changed since the job was queued
  def eligible_for_domain_setup?(business)
    # Check host type requirement
    unless business.host_type_custom_domain?
      Rails.logger.info "[CustomDomainSetupJob] Business #{business.id} is not custom domain type (#{business.host_type})"
      return false
    end

    # Check hostname is present
    unless business.hostname.present?
      Rails.logger.info "[CustomDomainSetupJob] Business #{business.id} has no hostname configured"
      return false
    end

    # Skip if setup already in progress or completed
    if business.cname_pending? || business.cname_monitoring? || business.cname_active?
      Rails.logger.info "[CustomDomainSetupJob] Business #{business.id} domain setup already in progress or completed (#{business.status})"
      return false
    end

    true
  end
end
