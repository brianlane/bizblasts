# frozen_string_literal: true

# Strategy pattern for domain verification status determination
# Encapsulates the complex logic for determining overall verification status
# based on DNS, Render, and health check results
class DomainVerificationStrategy
  def initialize(business)
    @business = business
  end

  # Determine verification status based on all check results
  # @param dns_result [Hash] Single-host DNS verification result (legacy CnameDnsChecker output)
  # @param render_result [Hash] Render verification result
  # @param health_result [Hash] Health check result
  # @param dual_result [Hash, nil] Optional DualDomainVerifier result containing
  #   per-host apex + www status. On Caddy this REPLACES the single-host
  #   dns_verified flag, because customers must independently configure A
  #   records for both apex and www and a one-sided pass would still leave
  #   www's TLS handshake hitting an unregistered host (Bugbot HIGH:
  #   "Activation ignores dual DNS checks"). On Render we keep the legacy
  #   behavior so existing call sites / specs that don't pass dual_result
  #   continue to work unchanged.
  # @return [Hash] Verification status with next actions
  def determine_status(dns_result, render_result, health_result, dual_result: nil)
    # Extract verification flags
    dns_verified = derive_dns_verified(dns_result, dual_result)
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

  # Provider-aware DNS verification gate.
  #
  # On Caddy a single-host pass is not enough: the apex and www records each
  # have their own A record requirement (see DualDomainVerifier comments and
  # CnameDnsChecker#apex_a_matches_expected? for the rationale). When the
  # caller supplies a dual_result, gate dns_verified on its overall_verified
  # flag so cname_success! can't fire when www still lacks its A record.
  # On Render (or when no dual_result is given) keep the legacy single-host
  # gate so existing controller actions / specs are unchanged.
  #
  # Exposed as a class method so callers that only need the gate value (e.g.
  # the live-status JSON in BusinessManager::Settings::BusinessController)
  # can derive `dns_check.verified` from the SAME logic the strategy uses to
  # gate cname_success! — otherwise the UI's "DNS verified" row can flash
  # green on one host while activation correctly stays blocked (Bugbot
  # MEDIUM: "DNS status flag ignores dual check").
  def self.dns_verified_for(dns_result, dual_result = nil)
    caddy_mode = defined?(DomainProvider) && DomainProvider.caddy?
    if caddy_mode && dual_result.is_a?(Hash) && dual_result.key?(:overall_verified)
      return dual_result[:overall_verified] == true
    end

    dns_result[:verified] == true
  end

  private

  def derive_dns_verified(dns_result, dual_result)
    self.class.dns_verified_for(dns_result, dual_result)
  end

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

  # Status copy referenced "CNAME record" and "Render verification" which is
  # only accurate on Render. On Caddy the customer configures apex + www A
  # records and the provider-verification step is BizBlasts' own domain
  # registry check rather than Render's. Pick provider-aware wording so the
  # live status panel stops contradicting the mailer/FAQ on Caddy deployments
  # (Bugbot MEDIUM: "Caddy status still says CNAME").
  def status_reason
    PROGRESS_COPY.dig(provider_key, verification_state) || 'Domain configuration is in progress'
  end

  PROGRESS_COPY = {
    render: {
      # SSL not ready cases
      all_pending:    'Waiting for CNAME record, Render verification, and health check',
      dns_only:       'DNS configured, waiting for Render verification and health check',
      render_only:    'Render verified, waiting for DNS and health check',
      health_only:    'Health verified, waiting for DNS and Render verification',
      dns_render:     'DNS and Render verified, waiting for domain to return HTTP 200',
      dns_health:     'DNS and health verified, waiting for Render verification',
      render_health:  'Render and health verified, waiting for DNS propagation',
      dns_render_http:'Domain working via HTTP - SSL certificate provisioning in progress',

      # SSL ready cases
      ssl_only:        'HTTPS working, waiting for DNS and Render verification',
      dns_ssl:         'DNS and HTTPS configured, waiting for Render verification',
      render_ssl:      'Render and HTTPS verified, waiting for DNS propagation',
      health_ssl:      'HTTPS working, waiting for DNS and Render verification',
      dns_render_ssl:  'DNS and Render verified, HTTPS working - finalizing activation',
      dns_health_ssl:  'DNS and HTTPS working, waiting for Render verification',
      render_health_ssl: 'Render and HTTPS verified, waiting for DNS propagation'
    },
    caddy: {
      # SSL not ready cases
      all_pending:    'Waiting for apex + www A records, BizBlasts verification, and health check',
      dns_only:       'DNS configured, waiting for BizBlasts verification and health check',
      render_only:    'BizBlasts verified, waiting for DNS and health check',
      health_only:    'Health verified, waiting for DNS and BizBlasts verification',
      dns_render:     'DNS and BizBlasts verified, waiting for domain to return HTTP 200',
      dns_health:     'DNS and health verified, waiting for BizBlasts verification',
      render_health:  'BizBlasts verified and healthy, waiting for DNS propagation',
      dns_render_http:'Domain working via HTTP - SSL certificate provisioning in progress',

      # SSL ready cases
      ssl_only:        'HTTPS working, waiting for DNS and BizBlasts verification',
      dns_ssl:         'DNS and HTTPS configured, waiting for BizBlasts verification',
      render_ssl:      'BizBlasts and HTTPS verified, waiting for DNS propagation',
      health_ssl:      'HTTPS working, waiting for DNS and BizBlasts verification',
      dns_render_ssl:  'DNS and BizBlasts verified, HTTPS working - finalizing activation',
      dns_health_ssl:  'DNS and HTTPS working, waiting for BizBlasts verification',
      render_health_ssl: 'BizBlasts and HTTPS verified, waiting for DNS propagation'
    }
  }.freeze
  private_constant :PROGRESS_COPY

  private

  def provider_key
    @provider_key ||= (defined?(DomainProvider) && DomainProvider.caddy?) ? :caddy : :render
  end

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
