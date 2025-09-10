# frozen_string_literal: true

# Strategy pattern for domain verification status determination
# Encapsulates the complex logic for determining overall verification status
# based on DNS, Render, and health check results
class DomainVerificationStrategy
  def initialize(business)
    @business = business
  end

  # Determine verification status based on all check results
  # @param dns_result [Hash] DNS verification result
  # @param render_result [Hash] Render verification result  
  # @param health_result [Hash] Health check result
  # @return [Hash] Verification status with next actions
  def determine_status(dns_result, render_result, health_result)
    # Extract verification flags
    dns_verified = dns_result[:verified] == true
    render_verified = render_result[:verified] == true
    health_verified = health_result[:healthy] == true

    # Determine overall status using policy rules
    verification_policy = create_verification_policy(dns_verified, render_verified, health_verified)
    
    {
      verified: verification_policy.verified?,
      should_continue: verification_policy.should_continue?,
      dns_verified: dns_verified,
      render_verified: render_verified,
      health_verified: health_verified,
      status_reason: verification_policy.status_reason
    }
  end

  private

  def create_verification_policy(dns_verified, render_verified, health_verified)
    # Check for success condition first
    if dns_verified && render_verified && health_verified
      return SuccessVerificationPolicy.new
    end

    # Check for timeout condition
    if @business.cname_check_attempts >= 11  # Next increment will be 12
      return TimeoutVerificationPolicy.new
    end

    # Return appropriate in-progress policy based on current state
    InProgressVerificationPolicy.new(dns_verified, render_verified, health_verified)
  end
end

# Base class for verification policies
class VerificationPolicy
  def verified?
    false
  end

  def should_continue?
    true
  end

  def status_reason
    'Checking domain verification'
  end
end

# Policy for successful verification (all checks passed)
class SuccessVerificationPolicy < VerificationPolicy
  def verified?
    true
  end

  def should_continue?
    false
  end

  def status_reason
    'Domain fully verified and responding with HTTP 200'
  end
end

# Policy for timeout (maximum attempts reached)
class TimeoutVerificationPolicy < VerificationPolicy
  def verified?
    false
  end

  def should_continue?
    false
  end

  def status_reason
    'Maximum verification attempts reached'
  end
end

# Policy for in-progress verification (continue monitoring)
class InProgressVerificationPolicy < VerificationPolicy
  def initialize(dns_verified, render_verified, health_verified)
    @dns_verified = dns_verified
    @render_verified = render_verified
    @health_verified = health_verified
  end

  def verified?
    false
  end

  def should_continue?
    true
  end

  def status_reason
    # Generate specific status message based on which checks have passed
    case verification_state
    when :all_pending
      'Waiting for CNAME record, Render verification, and health check'
    when :dns_only
      'DNS configured, waiting for Render verification and health check'
    when :render_only
      'Render verified, waiting for DNS and health check'
    when :health_only
      'Health verified, waiting for DNS and Render verification'
    when :dns_render
      'DNS and Render verified, waiting for domain to return HTTP 200'
    when :dns_health
      'DNS and health verified, waiting for Render verification'
    when :render_health
      'Render and health verified, waiting for DNS propagation'
    else
      'Domain configuration is in progress'
    end
  end

  private

  def verification_state
    case [@dns_verified, @render_verified, @health_verified]
    when [false, false, false]
      :all_pending
    when [true, false, false]
      :dns_only
    when [false, true, false]
      :render_only
    when [false, false, true]
      :health_only
    when [true, true, false]
      :dns_render
    when [true, false, true]
      :dns_health
    when [false, true, true]
      :render_health
    else
      :unknown
    end
  end
end
