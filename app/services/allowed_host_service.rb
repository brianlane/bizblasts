# frozen_string_literal: true

# AllowedHostService provides centralized domain validation for the multi-tenant platform.
#
# This service is the single source of truth for determining which hosts/domains are
# allowed to access the application. It prevents security vulnerabilities like CWE-20
# (Incomplete URL Substring Sanitization) by using strict structural validation instead
# of substring matching.
#
# The service validates three types of domains:
# 1. Main platform domains (bizblasts.com, www.bizblasts.com, etc.)
# 2. Platform subdomains (tenant.bizblasts.com) using strict regex validation
# 3. Custom domains registered in the Business table (custom-domain.com)
#
# Usage:
#   AllowedHostService.allowed?('tenant.bizblasts.com') # => true
#   AllowedHostService.allowed?('evil-bizblasts.com')   # => false
#   AllowedHostService.primary_domain                   # => 'bizblasts.com' (in production)
#
# Security:
# - Uses exact matching for main domains (no substring tricks)
# - Uses regex structural validation for subdomains (prevents evil-bizblasts.com)
# - Database-backed allowlist for custom domains
# - Environment-aware (production/development/test)
#
class AllowedHostService
  class << self
    # Returns the primary platform domain for the current environment
    # @return [String] The primary domain (e.g., 'bizblasts.com', 'lvh.me')
    def primary_domain
      if Rails.env.production?
        'bizblasts.com'
      elsif Rails.env.test?
        'example.com'
      else
        'lvh.me'
      end
    end

    # Returns all valid main platform domains for the current environment
    # These are domains where the platform itself is hosted (not tenant domains)
    # @return [Array<String>] List of main platform domains
    def main_domains
      if Rails.env.production?
        [
          'bizblasts.com',
          'www.bizblasts.com',
          'bizblasts.onrender.com' # Render deployment domain
        ]
      elsif Rails.env.test?
        [
          'example.com',
          'www.example.com',
          'test.host',
          'lvh.me',      # Some tests use lvh.me
          'www.lvh.me'   # Some tests use www.lvh.me
        ]
      else # development
        [
          'lvh.me',
          'www.lvh.me',
          'localhost'
        ]
      end
    end

    # Checks if a host is allowed to access the application
    # @param host [String] The hostname to validate (e.g., 'tenant.bizblasts.com')
    # @return [Boolean] true if the host is allowed, false otherwise
    def allowed?(host)
      return false if host.blank?

      host = normalize_host(host)

      # Check 1: Exact match against main platform domains
      return true if main_domain?(host)

      # Check 2: Valid platform subdomain (tenant.bizblasts.com, tenant.lvh.me, etc.)
      return true if valid_platform_subdomain?(host)

      # Check 3: Registered custom domain in database
      return true if valid_custom_domain?(host)

      false
    end

    # Checks if a host is one of the main platform domains
    # @param host [String] The hostname to check
    # @return [Boolean] true if this is a main platform domain
    def main_domain?(host)
      return false if host.blank?

      host = normalize_host(host)
      main_domains.include?(host)
    end

    # Checks if a host is a valid platform subdomain
    # Uses strict regex validation to prevent bypass attacks like:
    # - evil-bizblasts.com (fails: not a subdomain of bizblasts.com)
    # - mybizblasts.com.evil.org (fails: bizblasts.com is not at the end)
    #
    # @param host [String] The hostname to validate
    # @return [Boolean] true if this is a valid platform subdomain
    def valid_platform_subdomain?(host)
      return false if host.blank?

      host = normalize_host(host)

      # Get list of valid platform domains to check
      # In production: just bizblasts.com
      # In test/dev: both primary domain AND lvh.me (for test flexibility)
      domains_to_check = if Rails.env.production?
                          [primary_domain]
                        else
                          # In test/dev, check both example.com/lvh.me or lvh.me depending on environment
                          ['example.com', 'lvh.me'].uniq
                        end

      # Check each domain
      domains_to_check.each do |domain|
        # Build regex to match exactly one subdomain level (e.g., tenant.bizblasts.com)
        # Pattern: ^[a-z0-9-]+\.PRIMARY_DOMAIN$
        # This ensures:
        # - Starts with subdomain name (alphanumeric + hyphens)
        # - Has exactly one dot before the primary domain
        # - Ends with the primary domain (anchored with $)
        #
        # Examples that PASS:
        # - tenant.bizblasts.com
        # - my-business.lvh.me
        #
        # Examples that FAIL:
        # - evil-bizblasts.com (no dot before bizblasts.com)
        # - mybizblasts.com.evil.org (bizblasts.com not at the end)
        # - www.tenant.bizblasts.com (too many levels)
        subdomain_pattern = /\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.#{Regexp.escape(domain)}\z/i

        # Match against the pattern
        if host =~ subdomain_pattern
          # Extract subdomain part to check if it's 'www'
          # www is a main domain indicator, not a tenant subdomain
          subdomain_part = host.split('.').first
          return false if subdomain_part == 'www'
          return true
        end

        # Also allow development domains with ports
        if Rails.env.development? || Rails.env.test?
          # Remove port if present for validation
          host_without_port = host.split(':').first
          if host_without_port =~ subdomain_pattern
            subdomain_part = host_without_port.split('.').first
            return false if subdomain_part == 'www'
            return true
          end
        end
      end

      false
    end

    # Checks if a host is a registered custom domain
    # Custom domains are stored in the Business table with host_type='custom_domain'
    # and must be in an active state (cname_pending, cname_monitoring, or cname_active)
    #
    # Results are cached for 5 minutes to reduce database load on high-traffic sites.
    # Cache is automatically invalidated when business hostname or status changes via
    # the Business model's invalidate_allowed_host_cache callback.
    #
    # Cache implementation uses exact key deletion (not pattern matching) for:
    # - Better performance (no key scanning required)
    # - Universal compatibility (works with Memcached, Redis, etc.)
    #
    # @param host [String] The hostname to validate
    # @return [Boolean] true if this is a valid custom domain
    def valid_custom_domain?(host)
      return false if host.blank?
      return false unless business_table_exists?

      host = normalize_host(host)

      # Check both the exact host and variations (www/apex)
      # This handles cases where custom domain has www preference
      root = host.sub(/\Awww\./, '')
      candidates = [host, root, "www.#{root}"].uniq.map(&:downcase)

      # Cache for 5 minutes to reduce database load
      # Key includes all candidate hostnames to ensure proper cache hits
      # Cache is invalidated automatically via Business model callback
      cache_key = "allowed_host:custom_domain:#{candidates.sort.join(':')}"

      Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
        Business.where(host_type: 'custom_domain')
                .where(status: ['active', 'cname_pending', 'cname_monitoring', 'cname_active'])
                .where('LOWER(hostname) IN (?)', candidates)
                .exists?
      end
    rescue ActiveRecord::StatementInvalid, PG::Error => e
      # Database error - log and fail closed (deny access)
      Rails.logger.error "[AllowedHostService] Database error checking custom domain: #{e.message}"
      false
    end

    private

    # Normalizes a hostname for comparison
    # - Converts to lowercase
    # - Removes port numbers
    # - Strips whitespace
    # @param host [String] The hostname to normalize
    # @return [String] The normalized hostname
    def normalize_host(host)
      return '' if host.blank?

      # Remove port if present (e.g., 'localhost:3000' -> 'localhost')
      host = host.to_s.split(':').first

      # Lowercase and strip whitespace
      host.downcase.strip
    end

    # Checks if the businesses table exists in the database
    # @return [Boolean] true if the table exists
    def business_table_exists?
      ActiveRecord::Base.connection.table_exists?('businesses')
    rescue ActiveRecord::NoDatabaseError
      false
    end
  end
end
