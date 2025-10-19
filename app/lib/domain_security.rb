# frozen_string_literal: true

# DomainSecurity - Centralized domain validation for security-critical operations
#
# This module provides domain validation methods aligned with the JavaScript
# domain validation in turbo_tenant_helpers.js to ensure consistent security
# across client and server.
#
# Security Features:
# - Prevents domain spoofing attacks (e.g., "bizblasts.com.evil.com")
# - Validates platform domains (main domain and subdomains)
# - Validates custom domains (verified business domains)
# - CORS-safe origin validation
#
# Usage:
#   DomainSecurity.valid_platform_domain?("salon.bizblasts.com")  # => true
#   DomainSecurity.valid_platform_domain?("bizblasts.com.evil.com")  # => false
#   DomainSecurity.valid_custom_domain?("mysalon.com")  # => true (if verified)
#   DomainSecurity.allowed_cors_origins  # => Array of allowed origins
module DomainSecurity
  module_function

  # Get the platform domain for the current environment
  # Returns: "bizblasts.com" (production) or "lvh.me" (development/test)
  def platform_domain
    @platform_domain ||= Rails.env.production? ? 'bizblasts.com' : 'lvh.me'
  end

  # Get Render platform domain (for production deployments)
  def render_domain
    @render_domain ||= 'bizblasts.onrender.com'
  end

  # Validate if hostname is a valid platform domain
  # Prevents domain spoofing by using strict suffix matching
  #
  # Valid:
  #   - "bizblasts.com" (exact match)
  #   - "salon.bizblasts.com" (subdomain)
  #   - "www.bizblasts.com" (www subdomain)
  #
  # Invalid:
  #   - "bizblasts.com.evil.com" (attacker domain)
  #   - "evil-bizblasts.com" (not a subdomain)
  #   - "mybizblasts.com" (different domain)
  #
  # @param hostname [String] The hostname to validate
  # @return [Boolean] true if valid platform domain
  def valid_platform_domain?(hostname)
    return false if hostname.blank?

    normalized_host = hostname.to_s.downcase
    normalized_domain = platform_domain.downcase

    # Exact match
    return true if normalized_host == normalized_domain

    # Valid subdomain (ends with ".bizblasts.com" or ".lvh.me")
    return true if normalized_host.end_with?(".#{normalized_domain}")

    # Also check render domain for production
    if Rails.env.production?
      normalized_render = render_domain.downcase
      return true if normalized_host == normalized_render
      return true if normalized_host.end_with?(".#{normalized_render}")
    end

    false
  end

  # Validate if hostname is a verified custom domain
  # Only returns true for businesses with:
  # - host_type: 'custom_domain'
  # - DNS verified
  # - SSL certificate active
  # - Health check passing
  #
  # @param hostname [String] The hostname to validate
  # @return [Boolean] true if valid custom domain
  def valid_custom_domain?(hostname)
    return false if hostname.blank?
    return false unless defined?(Business)

    normalized_host = hostname.to_s.downcase

    # Check if this is a verified custom domain business
    Business.where(host_type: 'custom_domain')
            .where('LOWER(hostname) = ?', normalized_host)
            .where('status IN (?)', ['cname_active'])
            .where('domain_health_verified = ?', true)
            .exists?
  rescue StandardError => e
    Rails.logger.error "[DomainSecurity] Error validating custom domain: #{e.message}"
    false
  end

  # Validate if origin URL is allowed for CORS
  # Checks both platform domains and verified custom domains
  #
  # @param origin [String] The origin URL (e.g., "https://salon.bizblasts.com")
  # @return [Boolean] true if origin is allowed
  def valid_cors_origin?(origin)
    return false if origin.blank?

    begin
      uri = URI.parse(origin)
      hostname = uri.host

      # Allow platform domains (main domain + subdomains)
      return true if valid_platform_domain?(hostname)

      # Allow verified custom domains
      return true if valid_custom_domain?(hostname)

      false
    rescue URI::InvalidURIError => e
      Rails.logger.warn "[DomainSecurity] Invalid origin URI: #{origin} - #{e.message}"
      false
    end
  end

  # Get list of allowed CORS origins for ActionCable and API endpoints
  # Returns array of:
  # - Platform domains (main + www + render)
  # - Subdomain pattern matchers
  # - All verified custom domains
  #
  # PERFORMANCE: Results are cached for 5 minutes to reduce database queries
  # Cache is automatically invalidated when custom domains are added/updated
  #
  # @return [Array<String, Regexp>] Allowed origins
  def allowed_cors_origins
    # Use Rails.cache for thread-safe caching with TTL
    cache_key = 'domain_security:allowed_cors_origins'
    cache_ttl = 5.minutes

    Rails.cache.fetch(cache_key, expires_in: cache_ttl) do
      build_allowed_origins
    end
  rescue StandardError => e
    Rails.logger.error "[DomainSecurity] Error fetching cached origins: #{e.message}"
    # Fallback to building origins directly if cache fails
    build_allowed_origins
  end

  # Build the complete list of allowed CORS origins
  # This is the actual implementation called by allowed_cors_origins (cached)
  #
  # @return [Array<String, Regexp>] Allowed origins
  def build_allowed_origins
    origins = []

    # Platform domains (http and https)
    main = platform_domain
    ['https', 'http'].each do |protocol|
      origins << "#{protocol}://#{main}"
      origins << "#{protocol}://www.#{main}"
    end

    # Render domain (production only)
    if Rails.env.production?
      render = render_domain
      ['https', 'http'].each do |protocol|
        origins << "#{protocol}://#{render}"
        origins << "#{protocol}://www.#{render}"
      end

      # Render PR preview URLs (format: bizblasts-pr-123.onrender.com)
      origins << /https:\/\/bizblasts-pr-\d+\.onrender\.com/
      origins << /http:\/\/bizblasts-pr-\d+\.onrender\.com/
    end

    # Allow all subdomains of platform domain
    # SECURITY: Regex properly validates subdomain format:
    # - Must start/end with alphanumeric (no leading/trailing hyphens)
    # - Can contain hyphens in the middle
    # - Supports multi-level subdomains (e.g., api.v1.bizblasts.com)
    # Pattern: [subdomain.]bizblasts.com where subdomain = label(.label)*
    # Label format: alphanumeric start/end, hyphens allowed in middle
    main_escaped = Regexp.escape(main)
    # Subdomain label: [a-z0-9] followed by optional [a-z0-9-]* ending with [a-z0-9]
    # Supports single labels (salon) and multi-level (api.v1)
    subdomain_pattern = '[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*'
    origins << /https:\/\/#{subdomain_pattern}\.#{main_escaped}(:\d+)?/
    origins << /http:\/\/#{subdomain_pattern}\.#{main_escaped}(:\d+)?/

    # Add verified custom domains (if database is available)
    if defined?(Business) && Business.connection.table_exists?('businesses')
      custom_domains = Business.where(host_type: 'custom_domain')
                              .where('status IN (?)', ['cname_active'])
                              .where('domain_health_verified = ?', true)
                              .pluck(:hostname)
                              .compact

      custom_domains.each do |domain|
        origins << "https://#{domain}"
        origins << "https://www.#{domain}"
        # HTTP allowed in development/test only
        unless Rails.env.production?
          origins << "http://#{domain}"
          origins << "http://www.#{domain}"
        end
      end
    end

    origins.compact.uniq
  rescue StandardError => e
    Rails.logger.error "[DomainSecurity] Error building allowed origins: #{e.message}"
    # Return basic platform domains if database query fails
    [
      "https://#{platform_domain}",
      "https://www.#{platform_domain}",
      "http://#{platform_domain}",
      "http://www.#{platform_domain}"
    ]
  end

  # Clear the allowed origins cache
  # Call this when custom domains are added, updated, or removed
  # to ensure the cache reflects the latest verified domains
  #
  # Example usage:
  #   # In Business model after_commit callback
  #   DomainSecurity.clear_origins_cache
  def clear_origins_cache
    cache_key = 'domain_security:allowed_cors_origins'
    Rails.cache.delete(cache_key)
    Rails.logger.info "[DomainSecurity] Cleared allowed origins cache"
  rescue StandardError => e
    Rails.logger.error "[DomainSecurity] Error clearing origins cache: #{e.message}"
  end

  # Sanitize hostname for security
  # Removes potentially dangerous characters and normalizes
  #
  # @param hostname [String] Raw hostname input
  # @return [String] Sanitized hostname
  def sanitize_hostname(hostname)
    return '' if hostname.blank?

    hostname.to_s
            .downcase
            .gsub(/[^a-z0-9.-]/, '') # Only allow alphanumeric, dots, hyphens
            .gsub(/\.{2,}/, '.')     # No consecutive dots
            .gsub(/-{2,}/, '-')      # No consecutive hyphens
            .strip
  end

  # Check if request is from main platform domain (not a tenant subdomain)
  # Used to determine if user is on the main site vs a business site
  #
  # @param request [ActionDispatch::Request] The request object
  # @return [Boolean] true if on main domain
  def main_domain_request?(request)
    return false unless request

    host = request.host.to_s.downcase
    main = platform_domain.downcase

    # Exact match with main domain or www variant
    host == main || host == "www.#{main}"
  end

  # Extract subdomain from hostname (if valid platform domain)
  # Returns nil if not a valid subdomain
  #
  # @param hostname [String] The hostname to parse
  # @return [String, nil] Subdomain or nil
  def extract_subdomain(hostname)
    return nil unless valid_platform_domain?(hostname)

    normalized = hostname.to_s.downcase
    main = platform_domain.downcase

    # Remove main domain suffix
    if normalized.end_with?(".#{main}")
      subdomain = normalized.chomp(".#{main}")
      return subdomain unless subdomain == 'www'
    end

    nil
  end
end
