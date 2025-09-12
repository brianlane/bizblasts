# frozen_string_literal: true

# Job to continue domain rebuild process after Render cleanup delay
# Handles re-addition of domains and scheduling of verification jobs
class DomainRebuildContinueJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(business_id)
    business = Business.find(business_id)
    
    Rails.logger.info "[DomainRebuildContinueJob] Continuing domain rebuild for business #{business_id} (#{business.hostname})"
    
    # Validate business is still eligible
    unless business.host_type_custom_domain? && business.hostname.present?
      Rails.logger.warn "[DomainRebuildContinueJob] Business #{business_id} no longer eligible for domain rebuild"
      return
    end
    
    begin
      render_service = RenderDomainService.new
      apex_domain = business.hostname.sub(/^www\./, '')
      
      # Step 3: Re-add domains honoring canonical preference
      domains_to_add = determine_domains_to_add(business)
      domains_to_add.each do |domain_name|
        Rails.logger.info "[DomainRebuildContinueJob] Re-adding domain: #{domain_name}"
        render_service.add_domain(domain_name)
      end
      
      # Step 4: Schedule verification with 30-second delay between apex and www
      Rails.logger.info "[DomainRebuildContinueJob] Scheduling verification after rebuild"
      domains_to_verify = [apex_domain, "www.#{apex_domain}"]
      
      domains_to_verify.each_with_index do |domain_name, index|
        # Schedule verification with staggered delays: apex immediately, www after 30s
        wait_time = index * 30.seconds
        
        if wait_time > 0
          Rails.logger.info "[DomainRebuildContinueJob] Scheduling verification for #{domain_name} in #{wait_time} seconds"
          RenderDomainVerificationJob.set(wait: wait_time).perform_later(domain_name)
        else
          Rails.logger.info "[DomainRebuildContinueJob] Scheduling immediate verification for #{domain_name}"
          RenderDomainVerificationJob.perform_later(domain_name)
        end
      end
      
      Rails.logger.info "[DomainRebuildContinueJob] Domain rebuild completed for #{business.hostname}"
      
    rescue => e
      Rails.logger.error "[DomainRebuildContinueJob] Failed to continue domain rebuild: #{e.message}"
      raise e
    end
    
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[DomainRebuildContinueJob] Business #{business_id} not found: #{e.message}"
  rescue => e
    Rails.logger.error "[DomainRebuildContinueJob] Error for business #{business_id}: #{e.message}"
    raise e
  end

  private

  def determine_domains_to_add(business)
    apex_domain = business.hostname.sub(/^www\./, '')
    www_domain = "www.#{apex_domain}"
    
    case business.canonical_preference
    when 'www'
      # Add www domain as primary - Render will redirect apex → www
      Rails.logger.info "[DomainRebuildContinueJob] WWW canonical: adding www domain as primary"
      [www_domain]
    when 'apex'  
      # Add apex domain as primary - Render will redirect www → apex
      Rails.logger.info "[DomainRebuildContinueJob] Apex canonical: adding apex domain as primary"
      [apex_domain]
    else
      # Fallback: add stored hostname as-is
      Rails.logger.warn "[DomainRebuildContinueJob] Unknown canonical preference: #{business.canonical_preference}, using stored hostname"
      [business.hostname]
    end
  end
end