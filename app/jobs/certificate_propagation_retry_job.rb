# frozen_string_literal: true

# Job to retry Render domain verification when certificate propagation is delayed
# This handles cases where Render shows "Certificate Issued" but edge servers
# still return SSL handshake failures due to SNI propagation delays
class CertificatePropagationRetryJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(business_id, retry_count = 0)
    business = Business.find(business_id)
    
    Rails.logger.info "[CertificatePropagationRetryJob] Retry attempt #{retry_count} for business #{business_id} (#{business.hostname})"
    
    # Only proceed if business is still in monitoring state and eligible
    unless should_continue_retry?(business, retry_count)
      Rails.logger.info "[CertificatePropagationRetryJob] Stopping retries for business #{business_id}"
      return
    end
    
    # Test if SSL is now working
    if ssl_now_working?(business)
      Rails.logger.info "[CertificatePropagationRetryJob] SSL now working for #{business.hostname}, stopping retries"
      return
    end
    
    # After third retry (~35 minutes), rebuild domains from Render
    if retry_count >= 3
      Rails.logger.info "[CertificatePropagationRetryJob] Third retry reached, rebuilding domains for #{business.hostname}"
      rebuild_domains_in_render(business)
    else
      # Re-trigger Render verification for both domains
      trigger_render_verification(business)
    end
    
    # Schedule next retry if we haven't exceeded max attempts
    if retry_count < max_retry_attempts
      next_delay = calculate_next_delay(retry_count)
      Rails.logger.info "[CertificatePropagationRetryJob] Scheduling retry #{retry_count + 1} in #{next_delay} minutes for #{business.hostname}"
      
      CertificatePropagationRetryJob.set(wait: next_delay.minutes).perform_later(business_id, retry_count + 1)
    else
      Rails.logger.warn "[CertificatePropagationRetryJob] Max retries exceeded for #{business.hostname}, giving up"
    end
    
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[CertificatePropagationRetryJob] Business #{business_id} not found: #{e.message}"
  rescue => e
    Rails.logger.error "[CertificatePropagationRetryJob] Error for business #{business_id}: #{e.message}"
    raise e
  end

  private

  def should_continue_retry?(business, retry_count)
    # Stop if business is no longer monitoring or has been activated
    return false unless business.cname_monitoring? || business.cname_active?
    
    # Stop if we've exceeded max attempts
    return false if retry_count >= max_retry_attempts
    
    # Stop if business configuration changed (no longer custom domain)
    return false unless business.host_type_custom_domain? && business.hostname.present?
    
    true
  end

  def ssl_now_working?(business)
    canonical_domain = business.canonical_domain || business.hostname
    health_checker = DomainHealthChecker.new(canonical_domain)
    
    begin
      result = health_checker.check_health
      result[:healthy] && result[:ssl_ready]
    rescue => e
      Rails.logger.warn "[CertificatePropagationRetryJob] Health check failed for #{canonical_domain}: #{e.message}"
      false
    end
  end

  def trigger_render_verification(business)
    begin
      render_service = RenderDomainService.new
      apex_domain = business.hostname.sub(/^www\./, '')
      domains_to_verify = [apex_domain, "www.#{apex_domain}"]
      
      domains_to_verify.each_with_index do |domain_name, index|
        # Add 30-second delay between apex and www verification
        if index > 0
          Rails.logger.info "[CertificatePropagationRetryJob] Waiting 30 seconds before verifying #{domain_name}"
          sleep(30)
        end
        
        domain = render_service.find_domain_by_name(domain_name)
        if domain
          Rails.logger.info "[CertificatePropagationRetryJob] Re-triggering verification for: #{domain_name}"
          render_service.verify_domain(domain['id'])
        else
          Rails.logger.warn "[CertificatePropagationRetryJob] Domain not found in Render: #{domain_name}"
        end
      end
    rescue => e
      Rails.logger.error "[CertificatePropagationRetryJob] Failed to trigger verification: #{e.message}"
    end
  end

  def rebuild_domains_in_render(business)
    begin
      Rails.logger.info "[CertificatePropagationRetryJob] Starting domain rebuild for #{business.hostname}"
      
      render_service = RenderDomainService.new
      apex_domain = business.hostname.sub(/^www\./, '')
      domains_to_rebuild = [apex_domain, "www.#{apex_domain}"]
      
      # Step 1: Remove existing domains
      Rails.logger.info "[CertificatePropagationRetryJob] Removing existing domains from Render"
      domains_to_rebuild.each do |domain_name|
        domain = render_service.find_domain_by_name(domain_name)
        if domain
          Rails.logger.info "[CertificatePropagationRetryJob] Removing domain: #{domain_name}"
          render_service.remove_domain(domain['id'])
        end
      end
      
      # Step 2: Wait briefly for Render to process removals
      Rails.logger.info "[CertificatePropagationRetryJob] Waiting 10 seconds for Render cleanup"
      sleep(10)
      
      # Step 3: Re-add domains honoring canonical preference
      domains_to_add = determine_domains_to_add(business)
      domains_to_add.each do |domain_name|
        Rails.logger.info "[CertificatePropagationRetryJob] Re-adding domain: #{domain_name}"
        render_service.add_domain(domain_name)
      end
      
      # Step 4: Trigger verification with 30-second delay
      Rails.logger.info "[CertificatePropagationRetryJob] Triggering verification after rebuild"
      domains_to_rebuild.each_with_index do |domain_name, index|
        # Always wait 30 seconds between apex and www to prevent Render certificate race
        if index > 0
          Rails.logger.info "[CertificatePropagationRetryJob] Waiting 30 seconds before verifying #{domain_name}"
          sleep(30)
        end
        
        domain = render_service.find_domain_by_name(domain_name)
        if domain
          Rails.logger.info "[CertificatePropagationRetryJob] Verifying rebuilt domain: #{domain_name}"
          render_service.verify_domain(domain['id'])
        else
          Rails.logger.warn "[CertificatePropagationRetryJob] Rebuilt domain not found: #{domain_name}"
        end
      end
      
      Rails.logger.info "[CertificatePropagationRetryJob] Domain rebuild completed for #{business.hostname}"
      
    rescue => e
      Rails.logger.error "[CertificatePropagationRetryJob] Failed to rebuild domains: #{e.message}"
      raise e
    end
  end

  def determine_domains_to_add(business)
    apex_domain = business.hostname.sub(/^www\./, '')
    www_domain = "www.#{apex_domain}"
    
    case business.canonical_preference
    when 'www'
      # Add www domain as primary - Render will redirect apex → www
      Rails.logger.info "[CertificatePropagationRetryJob] WWW canonical: adding www domain as primary"
      [www_domain]
    when 'apex'  
      # Add apex domain as primary - Render will redirect www → apex
      Rails.logger.info "[CertificatePropagationRetryJob] Apex canonical: adding apex domain as primary"
      [apex_domain]
    else
      # Fallback: add stored hostname as-is
      Rails.logger.warn "[CertificatePropagationRetryJob] Unknown canonical preference: #{business.canonical_preference}, using stored hostname"
      [business.hostname]
    end
  end

  def max_retry_attempts
    # Retry for up to 2 hours: 5, 10, 20, 30, 30, 30 minutes = ~2 hours
    6
  end

  def calculate_next_delay(retry_count)
    # Progressive delays: 5, 10, 20, 30, 30, 30 minutes
    case retry_count
    when 0 then 5
    when 1 then 10  
    when 2 then 20
    else 30
    end
  end
end
