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
  # ▸ Sub-domain tenants → "subdomain.example.com"
  # ▸ Custom-domain tenants → "custom-domain.com"
  def host_for(business, request)
    return unless business

    if business.host_type_subdomain?
      "#{business.subdomain}.#{request.domain}"
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
end
