# frozen_string_literal: true

# Service for coordinating DNS monitoring and state transitions
# Handles the periodic checking and status updates during CNAME setup
class DomainMonitoringService
  class MonitoringError < StandardError; end

  def initialize(business)
    @business = business
    @dns_checker = CnameDnsChecker.new(@business.hostname)
    @dual_verifier = DualDomainVerifier.new(@business.hostname)
    @render_service = RenderDomainService.new
    @health_checker = DomainHealthChecker.new(@business.hostname)
    @verification_strategy = DomainVerificationStrategy.new(@business)
  end

  # Perform a single monitoring check
  # @return [Hash] Check result with next actions
  def perform_check!
    Rails.logger.info "[DomainMonitoringService] Checking domain: #{@business.hostname}"

    begin
      # Validate business is eligible for monitoring
      validate_monitoring_state!

      # Perform DNS verification (legacy single check)
      dns_result = @dns_checker.verify_cname

      # Perform comprehensive dual domain verification
      dual_result = @dual_verifier.verify_both_domains

      # Check Render API verification status
      render_result = check_render_verification

      # Trigger verification for any unverified domains
      trigger_render_verification_if_needed

      # Perform domain health check
      health_result = check_domain_health

      # Determine overall verification status using strategy pattern
      verification_result = @verification_strategy.determine_status(dns_result, render_result, health_result)

      # Update business state based on results
      update_business_state!(verification_result)

      # Return result for job scheduling decisions
      {
        success: true,
        verified: verification_result[:verified],
        should_continue: verification_result[:should_continue],
        attempts: @business.cname_check_attempts,
        max_attempts: 12,
        dns_result: dns_result,
        dual_verification: dual_result,
        render_result: render_result,
        health_result: health_result,
        next_check_in: verification_result[:should_continue] ? '5 minutes' : 'stopped'
      }

    rescue => e
      Rails.logger.error "[DomainMonitoringService] Monitoring check failed: #{e.message}"
      
      {
        success: false,
        error: e.message,
        attempts: @business.cname_check_attempts,
        should_continue: false
      }
    end
  end

  # Stop monitoring and update business status
  # @param reason [String] Reason for stopping monitoring
  def stop_monitoring!(reason = 'Manual stop')
    Rails.logger.info "[DomainMonitoringService] Stopping monitoring for #{@business.hostname}: #{reason}"

    @business.stop_cname_monitoring!
  end

  # Get detailed monitoring status
  # @return [Hash] Comprehensive monitoring information
  def monitoring_status
    {
      business_id: @business.id,
      domain: @business.hostname,
      status: @business.status,
      monitoring_active: @business.cname_monitoring_active?,
      attempts: @business.cname_check_attempts,
      max_attempts: 12,
      time_remaining: time_remaining_estimate,
      can_check: @business.cname_due_for_check?,
      last_updated: @business.updated_at
    }
  end

  private

  def validate_monitoring_state!
    unless @business.cname_monitoring_active?
      raise MonitoringError, 'Business monitoring is not active'
    end

    unless @business.cname_monitoring?
      raise MonitoringError, 'Business is not in monitoring status'
    end

    if @business.cname_check_attempts >= 12
      raise MonitoringError, 'Maximum monitoring attempts exceeded'
    end
  end

  def check_render_verification
    Rails.logger.debug "[DomainMonitoringService] Checking Render verification status"

    begin
      # Find domain in Render
      domain = @render_service.find_domain_by_name(@business.hostname)
      
      if domain.nil?
        return {
          found: false,
          verified: false,
          error: 'Domain not found in Render service'
        }
      end

      # Try to verify domain
      verification_result = @render_service.verify_domain(domain['id'])
      
      {
        found: true,
        verified: verification_result['verified'] == true,
        domain_id: domain['id'],
        verification_data: verification_result
      }

    rescue => e
      Rails.logger.warn "[DomainMonitoringService] Render verification check failed: #{e.message}"
      
      {
        found: false,
        verified: false,
        error: e.message
      }
    end
  end

  def check_domain_health
    Rails.logger.debug "[DomainMonitoringService] Checking domain health status"

    begin
      # Perform health check
      health_result = @health_checker.check_health

      Rails.logger.info "[DomainMonitoringService] Health check result for #{@business.hostname}: healthy=#{health_result[:healthy]}, status=#{health_result[:status_code]}"
      
      health_result
    rescue => e
      Rails.logger.warn "[DomainMonitoringService] Domain health check failed: #{e.message}"
      
      {
        healthy: false,
        error: e.message,
        checked_at: Time.current
      }
    end
  end


  def update_business_state!(verification_result)
    @business.increment_cname_check!

    # Update health status regardless of overall verification result
    if verification_result[:health_verified]
      @business.mark_domain_health_status!(true)
    else
      @business.mark_domain_health_status!(false)
    end

    if verification_result[:verified]
      # Success - activate domain (health is already verified above)
      Rails.logger.info "[DomainMonitoringService] Domain fully verified and healthy: #{@business.hostname}"
      
      @business.cname_success!
      send_activation_success_email!
      
    elsif !verification_result[:should_continue]
      # Timeout - stop monitoring and notify
      Rails.logger.warn "[DomainMonitoringService] Domain verification timed out: #{@business.hostname}"
      
      @business.cname_timeout!
      send_timeout_help_email!
      
    else
      # Continue monitoring - just update the attempts counter
      Rails.logger.debug "[DomainMonitoringService] Continuing monitoring: #{@business.hostname} (attempt #{@business.cname_check_attempts}/12) - Health: #{verification_result[:health_verified]}"
    end
  end

  def send_activation_success_email!
    owner = @business.users.where(role: 'manager').first
    
    if owner
      DomainMailer.activation_success(@business, owner).deliver_now
    else
      Rails.logger.warn "[DomainMonitoringService] No owner found for success email"
    end
  end

  def send_timeout_help_email!
    owner = @business.users.where(role: 'manager').first
    
    if owner
      DomainMailer.timeout_help(@business, owner).deliver_now
    else
      Rails.logger.warn "[DomainMonitoringService] No owner found for timeout email"
    end
  end

  def time_remaining_estimate
    return 'Complete' unless @business.cname_monitoring_active?
    
    attempts_left = 12 - @business.cname_check_attempts
    minutes_left = attempts_left * 5
    
    if minutes_left <= 0
      'Timeout'
    elsif minutes_left < 60
      "~#{minutes_left} minutes"
    else
      hours = minutes_left / 60
      remaining_minutes = minutes_left % 60
      "~#{hours}h #{remaining_minutes}m"
    end
  end

  def trigger_render_verification_if_needed
    Rails.logger.info "[DomainMonitoringService] Checking if Render verification needed"

    begin
      # Find all domains related to our hostname (both apex and www)
      apex_domain = @business.hostname
      www_domain = "www.#{apex_domain}"
      
      domains_to_check = [apex_domain, www_domain]
      
      domains_to_check.each do |domain_name|
        domain = @render_service.find_domain_by_name(domain_name)
        if domain
          # Check if domain needs verification
          unless domain['verificationStatus'] == 'verified'
            Rails.logger.info "[DomainMonitoringService] Triggering verification for unverified domain: #{domain_name}"
            
            begin
              result = @render_service.verify_domain(domain['id'])
              if result['verified']
                Rails.logger.info "[DomainMonitoringService] ✅ Domain verified successfully: #{domain_name}"
              else
                Rails.logger.info "[DomainMonitoringService] ⚠️ Domain verification still pending: #{domain_name}"
              end
            rescue => e
              Rails.logger.warn "[DomainMonitoringService] Domain verification failed for #{domain_name}: #{e.message}"
            end
          else
            Rails.logger.debug "[DomainMonitoringService] Domain already verified: #{domain_name}"
          end
        end
      end
    rescue => e
      Rails.logger.error "[DomainMonitoringService] Error during verification check: #{e.message}"
    end
  end
end