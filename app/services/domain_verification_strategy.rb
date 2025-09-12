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
    ssl_ready = health_result[:ssl_ready] == true

    # Determine overall status using policy rules
    verification_policy = create_verification_policy(dns_verified, render_verified, health_verified, ssl_ready)
    
    {
      verified: verification_policy.verified?,
      should_continue: verification_policy.should_continue?,
      dns_verified: dns_verified,
      render_verified: render_verified,
      health_verified: health_verified,
      ssl_ready: ssl_ready,
      status_reason: verification_policy.status_reason
    }
  end

  private

  def create_verification_policy(dns_verified, render_verified, health_verified, ssl_ready)
    # Check for full success condition (all verified including SSL)
    if dns_verified && render_verified && health_verified && ssl_ready
      return SuccessVerificationPolicy.new
    end

    # Check for SSL-pending condition (everything works but SSL not ready yet)
    if dns_verified && render_verified && health_verified && !ssl_ready
      return SslPendingVerificationPolicy.new
    end

    # Check for timeout condition
    if @business.cname_check_attempts >= 11  # Next increment will be 12
      return TimeoutVerificationPolicy.new
    end

    # Return appropriate in-progress policy based on current state
    InProgressVerificationPolicy.new(dns_verified, render_verified, health_verified, ssl_ready)
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
    'Domain fully verified and responding with HTTPS (SSL ready)'
  end
end

# Policy for SSL pending (domain works but SSL certificate not ready)
class SslPendingVerificationPolicy < VerificationPolicy
  def verified?
    false  # Don't activate until SSL is ready
  end

  def should_continue?
    true   # Keep monitoring for SSL readiness
  end

  def status_reason
    'Domain responding via HTTP - SSL certificate provisioning in progress'
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
  def initialize(dns_verified, render_verified, health_verified, ssl_ready = false)
    @dns_verified = dns_verified
    @render_verified = render_verified
    @health_verified = health_verified
    @ssl_ready = ssl_ready
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
    # SSL not ready cases
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
    when :dns_render_http
      'Domain working via HTTP - SSL certificate provisioning in progress'
    
    # SSL ready cases
    when :ssl_only
      'HTTPS working, waiting for DNS and Render verification'
    when :dns_ssl
      'DNS and HTTPS configured, waiting for Render verification'
    when :render_ssl
      'Render and HTTPS verified, waiting for DNS propagation'
    when :health_ssl
      'HTTPS working, waiting for DNS and Render verification'
    when :dns_render_ssl
      'DNS and Render verified, HTTPS working - finalizing activation'
    when :dns_health_ssl
      'DNS and HTTPS working, waiting for Render verification'
    when :render_health_ssl
      'Render and HTTPS verified, waiting for DNS propagation'
    else
      'Domain configuration is in progress'
    end
  end

  private

  def verification_state
    case [@dns_verified, @render_verified, @health_verified, @ssl_ready]
    # SSL not ready cases
    when [false, false, false, false]
      :all_pending
    when [true, false, false, false]
      :dns_only
    when [false, true, false, false]
      :render_only
    when [false, false, true, false]
      :health_only
    when [true, true, false, false]
      :dns_render
    when [true, false, true, false]
      :dns_health
    when [false, true, true, false]
      :render_health
    when [true, true, true, false]
      :dns_render_http  # Everything works but SSL pending
    
    # SSL ready cases (health check passed with HTTPS)
    when [false, false, false, true]
      :ssl_only
    when [true, false, false, true]
      :dns_ssl
    when [false, true, false, true]
      :render_ssl
    when [false, false, true, true]
      :health_ssl
    when [true, true, false, true]
      :dns_render_ssl
    when [true, false, true, true]
      :dns_health_ssl
    when [false, true, true, true]
      :render_health_ssl
    # Note: [true, true, true, true] is handled by SuccessVerificationPolicy
    
    else
      :unknown
    end
  end
end
