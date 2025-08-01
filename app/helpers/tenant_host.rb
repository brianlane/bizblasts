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
      # Always use the main application domain for subdomains, not the current request domain
      # This prevents issues like generating "subdomain.custom-domain.com" when the current 
      # request is from a custom domain business
      main_domain = Rails.application.config.main_domain.split(':').first
      
      # Use subdomain field if present, otherwise fall back to hostname
      subdomain_part = business.subdomain.presence || business.hostname.presence
      
      # Return nil if no valid subdomain part to prevent invalid URLs like ".lvh.me"
      return unless subdomain_part
      
      "#{subdomain_part}.#{main_domain}"
    else
      # For custom-domain tenants, the hostname column already contains the full
      # domain (e.g. "customdomain.com") so we can return it verbatim.
      # Return nil if hostname is blank to prevent invalid URLs
      business.hostname.presence
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
    # In test environment, use Capybara server port if available
    if port.nil? && request.nil?
      if Rails.env.test? && defined?(Capybara) && Capybara.server_port
        port = Capybara.server_port
      elsif Rails.env.development?
        port = 3000
      end
    end

    port_str = if port.nil?
                 ''
               elsif (protocol == 'https://' && port == 443) || (protocol == 'http://' && port == 80)
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
    # Use configured main domain for consistency across environments
    main_domain = Rails.application.config.main_domain.split(':').first

    # Include non-standard port for development and tests
    port_str = if request&.port && ![80, 443].include?(request.port)
                 ":#{request.port}"
               else
                 ''
               end

    # Ensure path starts with a slash
    path = path.start_with?('/') ? path : "/#{path}"

    "#{request.protocol}#{main_domain}#{port_str}#{path}"
  end
end
