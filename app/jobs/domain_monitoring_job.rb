# frozen_string_literal: true

# Background job for monitoring CNAME DNS setup progress
# Runs every 5 minutes to check if custom domain DNS is properly configured
class DomainMonitoringJob < ApplicationJob
  queue_as :default

  # Maximum number of retry attempts if the job fails
  retry_on StandardError, wait: 2.minutes, attempts: 3

  # Discard job after max attempts to prevent infinite retries
  discard_on DomainMonitoringService::MonitoringError

  def perform(business_id)
    Rails.logger.info "[DomainMonitoringJob] Starting monitoring check for business #{business_id}"

    business = Business.find_by(id: business_id)
    
    if business.nil?
      Rails.logger.error "[DomainMonitoringJob] Business #{business_id} not found"
      return
    end

    # Skip if monitoring is no longer needed
    unless should_continue_monitoring?(business)
      Rails.logger.info "[DomainMonitoringJob] Monitoring no longer needed for business #{business_id}"
      return
    end

    # Skip if not due for check yet
    unless business.cname_due_for_check?
      Rails.logger.debug "[DomainMonitoringJob] Check not due yet for business #{business_id}"
      schedule_next_check(business)
      return
    end

    # Perform the monitoring check
    monitoring_service = DomainMonitoringService.new(business)
    result = monitoring_service.perform_check!

    Rails.logger.info "[DomainMonitoringJob] Check completed for business #{business_id}: verified=#{result[:verified]}, continue=#{result[:should_continue]}"

    # Schedule next check if monitoring should continue
    if result[:should_continue]
      schedule_next_check(business)
    else
      Rails.logger.info "[DomainMonitoringJob] Monitoring completed for business #{business_id}"
    end

  rescue Business::RecordNotFound => e
    Rails.logger.error "[DomainMonitoringJob] Business #{business_id} not found: #{e.message}"
  rescue => e
    Rails.logger.error "[DomainMonitoringJob] Error monitoring business #{business_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n") if Rails.env.development?
    
    # Don't schedule next check on error to prevent runaway jobs
    raise e
  end

  # Class method to start monitoring for a business
  def self.start_monitoring(business_id)
    Rails.logger.info "[DomainMonitoringJob] Starting monitoring for business #{business_id}"
    perform_later(business_id)
  end

  # Class method to stop monitoring for a business
  def self.stop_monitoring(business_id)
    Rails.logger.info "[DomainMonitoringJob] Stopping monitoring for business #{business_id}"
    
    business = Business.find_by(id: business_id)
    return unless business

    business.stop_cname_monitoring!
  end

  # Process all businesses that need monitoring
  def self.monitor_all_pending
    Rails.logger.info "[DomainMonitoringJob] Processing all pending monitoring checks"
    
    businesses_needing_monitoring = Business.monitoring_needed.where(
      'cname_check_attempts < ? AND (updated_at IS NULL OR updated_at <= ?)', 
      12, 
      5.minutes.ago
    )

    Rails.logger.info "[DomainMonitoringJob] Found #{businesses_needing_monitoring.count} businesses needing monitoring"

    businesses_needing_monitoring.each do |business|
      begin
        perform_later(business.id)
      rescue => e
        Rails.logger.error "[DomainMonitoringJob] Failed to queue monitoring for business #{business.id}: #{e.message}"
      end
    end
  end

  private

  def should_continue_monitoring?(business)
    # Must be in monitoring status
    return false unless business.cname_monitoring?

    # Must have monitoring flag enabled
    return false unless business.cname_monitoring_active?

    # Must not have exceeded max attempts
    return false if business.cname_check_attempts >= 12

    # Must be premium tier
    return false unless business.premium_tier?

    # Must be custom domain type
    return false unless business.host_type_custom_domain?

    true
  end

  def schedule_next_check(business)
    # Schedule next check in 5 minutes
    Rails.logger.debug "[DomainMonitoringJob] Scheduling next check for business #{business.id} in 5 minutes"
    
    DomainMonitoringJob.set(wait: 5.minutes).perform_later(business.id)
  end
end