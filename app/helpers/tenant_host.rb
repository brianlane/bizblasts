# frozen_string_literal: true

# Utility methods for generating the correct host (and full URLs)
# for a Business object based on its host_type.
#
# Usage:
#   host   = TenantHost.host_for(business, request)
#   url    = TenantHost.url_for(business, request, '/manage/dashboard')
#
# This centralises the host-type logic so we don’t have to repeat the
# `host_type_subdomain? ? business.subdomain : business.hostname` dance
# throughout the codebase.
module TenantHost
  module_function

  # Returns the host (without protocol) appropriate for the business.
  # ▸ Sub-domain tenants → "subdomain.lvh.me" (dev) or "subdomain.bizblasts.com" (prod)
  # ▸ Custom-domain tenants → "custom-domain.com"
  def host_for(business, request)
    return unless business

    if business.host_type_subdomain?
      # Use the request's domain for sub-domains so the helper works in
      # development, test (example.com) and production (bizblasts.com)
      request_domain = request&.respond_to?(:domain) ? request.domain : nil

      # Normalize common Rails test domain to example.com for consistency in specs
      if request_domain == 'test.host'
        request_domain = 'example.com'
      end

      # Fallback to a sensible default if request.domain is not available
      main_domain = request_domain.presence || (Rails.env.development? ? 'lvh.me' : 'bizblasts.com')

      sub_part = business.subdomain.presence || business.hostname
      "#{sub_part}.#{main_domain}"
    else
      # For custom-domain tenants, the hostname column already contains the full
      # domain (e.g. "customdomain.com") so we can return it verbatim.
      business.hostname
    end
  end

  # Builds a full URL (with protocol) for the given path (defaults to root).
  def url_for(business, request, path = '')
    host = host_for(business, request)
    return path unless host # Fallback if business is nil

    # Ensure path starts with a slash (unless it is blank)
    path = path.to_s
    path = "" if path == "/" # Treat single slash as root (no trailing slash)
    path = "/#{path}" if path.present? && !path.start_with?("/")
    # Remove leading slash for query-only paths (e.g., '/?ref=CODE' → '?ref=CODE')
    path = path[1..] if path.start_with?("/?")

    # Include port when:
    # ▸ Non-standard ports (e.g., 3000)
    # ▸ Explicit 80 on http (for tests that assert :80)
    # We omit the port only for the canonical HTTPS 443 to keep URLs clean.
    port = request&.respond_to?(:port) ? request.port : nil
    protocol = if request&.respond_to?(:protocol)
                 request.protocol
               else
                 Rails.env.production? ? 'https://' : 'http://'
               end

    # Default to :3000 in development when no request object is provided (used in specs)
    if port.nil? && request.nil? && Rails.env.development?
      port = 3000
    end

    port_str = if port.nil?
                 ''
               elsif protocol == 'https://' && port == 443
                 ''
               else
                 ":#{port}"
               end

    "#{protocol}#{host}#{port_str}#{path}"
  end

  # Alias for compatibility and ease of grep-replace operations.
  #
  # @param business [Business] The business object
  # @param request [ActionDispatch::Request] The current request object
  # @param path [String] The path to append (defaults to root '/')
  # @return [String] The complete URL
  # @see #url_for
  alias_method :full_url, :url_for

  # Generates a URL for the main application domain (no subdomain/tenant).
  #
  # @param request [ActionDispatch::Request] The current request object
  # @param path [String] The path to append (defaults to root '/')
  # @return [String] The complete URL on the main domain
  #
  # @example Development
  #   main_domain_url_for(request, '/dashboard') #=> "http://lvh.me:3000/dashboard"
  #
  # @example Production
  #   main_domain_url_for(request, '/admin') #=> "https://bizblasts.com/admin"
  def main_domain_url_for(request, path = '/')
    # Determine main domain based on environment
    main_domain = if Rails.env.development? || Rails.env.test?
                    'lvh.me'
                  else
                    'bizblasts.com'
                  end

    # Include non-standard port for development
    port_str = if request.port && ![80, 443].include?(request.port)
                 ":#{request.port}"
               else
                 ''
               end

    # Ensure path starts with a slash
    path = path.start_with?('/') ? path : "/#{path}"

    "#{request.protocol}#{main_domain}#{port_str}#{path}"
  end
end
