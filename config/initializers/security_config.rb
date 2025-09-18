# frozen_string_literal: true

# Security configuration for cross-domain authentication
class SecurityConfig
  # IP matching strategy for authentication tokens
  # With Cloudflare trusted proxies configured, request.remote_ip should give us
  # the real client IP consistently across domains, making strict matching viable
  def self.strict_ip_match?
    # Default to strict matching in all environments now that we use real client IPs
    # Can be overridden with AUTH_TOKEN_STRICT_IP=false if needed
    ENV.fetch('AUTH_TOKEN_STRICT_IP', 'true') == 'true'
  end
  
  # Helper method to get the real client IP from a request
  # Uses remote_ip which respects trusted proxies (Cloudflare)
  def self.client_ip(request)
    request.remote_ip
  end
end
