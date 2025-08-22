# frozen_string_literal: true

# Service for coordinating DNS monitoring and state transitions
# Handles the periodic checking and status updates during CNAME setup
class DomainMonitoringService
  class MonitoringError < StandardError; end

  def initialize(business)
    @business = business
    @dns_checker = CnameDnsChecker.new(@business.hostname)
    @render_service = RenderDomainService.new
  end

  # Perform a single monitoring check
  # @return [Hash] Check result with next actions
  def perform_check!
    Rails.logger.info "[DomainMonitoringService] Checking domain: #{@business.hostname}"

    begin
      # Validate business is eligible for monitoring
      validate_monitoring_state!

      # Perform DNS verification
      dns_result = @dns_checker.verify_cname

      # Check Render API verification status
      render_result = check_render_verification

      # Determine overall verification status
      verification_result = determine_verification_status(dns_result, render_result)

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
        render_result: render_result,
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

  def determine_verification_status(dns_result, render_result)
    verified = false
    should_continue = true
    status_reason = 'Checking DNS and Render verification'

    # Check if DNS is properly configured
    dns_verified = dns_result[:verified] == true

    # Check if Render has verified the domain
    render_verified = render_result[:verified] == true

    if dns_verified && render_verified
      # Both DNS and Render are verified - success!
      verified = true
      should_continue = false
      status_reason = 'Domain verified successfully'
    elsif @business.cname_check_attempts >= 11  # Next increment will be 12
      # Reached maximum attempts - timeout
      verified = false
      should_continue = false
      status_reason = 'Maximum verification attempts reached'
    else
      # Continue monitoring
      verified = false
      should_continue = true
      
      if !dns_verified && !render_verified
        status_reason = 'Waiting for CNAME record and Render verification'
      elsif dns_verified && !render_verified
        status_reason = 'DNS configured, waiting for Render verification'
      elsif !dns_verified && render_verified
        status_reason = 'Render ready, waiting for DNS propagation'
      end
    end

    {
      verified: verified,
      should_continue: should_continue,
      dns_verified: dns_verified,
      render_verified: render_verified,
      status_reason: status_reason
    }
  end

  def update_business_state!(verification_result)
    @business.increment_cname_check!

    if verification_result[:verified]
      # Success - activate domain
      Rails.logger.info "[DomainMonitoringService] Domain verified successfully: #{@business.hostname}"
      
      @business.cname_success!
      send_activation_success_email!
      
    elsif !verification_result[:should_continue]
      # Timeout - stop monitoring and notify
      Rails.logger.warn "[DomainMonitoringService] Domain verification timed out: #{@business.hostname}"
      
      @business.cname_timeout!
      send_timeout_help_email!
      
    else
      # Continue monitoring - just update the attempts counter
      Rails.logger.debug "[DomainMonitoringService] Continuing monitoring: #{@business.hostname} (attempt #{@business.cname_check_attempts}/12)"
    end
  end

  def send_activation_success_email!
    owner = @business.users.where(role: ['manager', 'client']).first
    
    if owner
      DomainMailer.activation_success(@business, owner).deliver_now
    else
      Rails.logger.warn "[DomainMonitoringService] No owner found for success email"
    end
  end

  def send_timeout_help_email!
    owner = @business.users.where(role: ['manager', 'client']).first
    
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
end