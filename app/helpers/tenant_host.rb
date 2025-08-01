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
      main_domain = if Rails.env.development? || Rails.env.test?
                      'lvh.me'
                    else
                      'bizblasts.com'
                    end
      "#{business.subdomain}.#{main_domain}"
    else
      business.hostname
    end
  end

  # Builds a full URL (with protocol) for the given path (defaults to root).
  def url_for(business, request, path = '/')
    host = host_for(business, request)
    return path unless host # Fallback if business is nil

    # Include non-standard port (e.g., :3000 in development) so links work in dev / test.
    port_str = if request.port && ![80, 443].include?(request.port)
                 ":#{request.port}"
               else
                 ''
               end

    "#{request.protocol}#{host}#{port_str}#{path}"
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
