# frozen_string_literal: true

require 'cgi'

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
      main_domain = if Rails.env.production?
                     'bizblasts.com'
                   else
                     Rails.application.config.main_domain.split(':').first
                   end
      
      # Use subdomain field if present, otherwise fall back to hostname
      subdomain_part = business.subdomain.presence || business.hostname.presence
      
      # Return nil if no valid subdomain part to prevent invalid URLs like ".lvh.me"
      return unless subdomain_part
      
      "#{subdomain_part}.#{main_domain}"
    else
      # For custom-domain tenants, only use the custom domain if it's fully working
      # Otherwise fall back to subdomain to prevent broken redirects
      if business.custom_domain_allow?
        # Custom domain is working (DNS + SSL + health verified)
        business.hostname.presence
      else
        # Custom domain not ready, fall back to subdomain
        Rails.logger.info "[TenantHost] Custom domain #{business.hostname} not ready, using subdomain fallback"
        main_domain = if Rails.env.production?
                       'bizblasts.com'
                     else
                       Rails.application.config.main_domain.split(':').first
                     end
        
        subdomain_part = business.subdomain.presence || business.hostname.presence
        return unless subdomain_part
        
        "#{subdomain_part}.#{main_domain}"
      end
    end
  end

  # Builds a full URL (with protocol) for the given path (defaults to root).
  def url_for(business, request, path = '')
    host = host_for(business, request)
    return path unless host # Fallback if business is nil

    # Ensure path starts with a slash (unless it is blank)
    path = path.to_s
    path = "/#{path}" if path.present? && !path.start_with?("/")
    # Remove leading slash for query-only paths (e.g., '/?ref=CODE' → '?ref=CODE')
    path = path[1..] if path.start_with?("/?")

    # For custom domains, use HTTPS (or HTTP in development/test) and omit non-standard ports from request
    # This prevents inheriting development ports (like :3000) in custom domain URLs
    if business&.host_type_custom_domain?
      protocol = if (Rails.env.development? || Rails.env.test?) && request&.protocol == 'http://'
                   'http://'
                 else
                   'https://'
                 end
      port_str = ''
    else
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
      # In test mode, leave port nil to avoid Capybara server conflicts
      if port.nil? && request.nil? && Rails.env.development?
        port = 3000
      end

      port_str = if port.nil?
                   ''
                 elsif port == 80 || (protocol == 'https://' && port == 443)
                   ''
                 else
                   ":#{port}"
                 end
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

  # Returns true if the given host corresponds to the platform’s main domain in
  # the current environment. This helps controllers avoid duplicating the
  # environment-specific host lists.
  #
  # @param host [String] The hostname to evaluate (e.g. "biztest.bizblasts.com")
  # @return [Boolean] Whether the host is considered the main application
  #   domain (no tenant context)
  def main_domain?(host)
    host = host.to_s.downcase

    if Rails.env.development? || Rails.env.test?
      %w[lvh.me www.lvh.me test.host example.com www.example.com].include?(host)
    else
      %w[bizblasts.com www.bizblasts.com bizblasts.onrender.com].include?(host)
    end
  end

  module_function :main_domain?

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
    # Use request's host if it's already a main domain, otherwise use configured main domain
    # This preserves the request context when routing through auth bridge
    main_domain = if request&.host && main_domain?(request.host)
                     request.host
                   elsif Rails.env.production?
                     'bizblasts.com'
                   else
                     Rails.application.config.main_domain.split(':').first
                   end

    # Include non-standard port for development and tests
    # Omit port 80 (for both HTTP and HTTPS) and port 443 (for HTTPS)
    port_str = if request&.port && request.port != 80 && !(request.protocol == 'https://' && request.port == 443)
                 ":#{request.port}"
               else
                 ''
               end

    # Ensure path starts with a slash
    path = path.start_with?('/') ? path : "/#{path}"

    "#{request.protocol}#{main_domain}#{port_str}#{path}"
  end
  
  # Generates a URL for a business that handles cross-domain authentication.
  # If the user is signed in on the main domain and the business uses a custom domain,
  # this will route through the authentication bridge to transfer the session.
  #
  # @param business [Business] The business object
  # @param request [ActionDispatch::Request] The current request object
  # @param path [String] The path to append (defaults to root '/')
  # @param user_signed_in [Boolean] Whether the current user is signed in
  # @return [String] The complete URL, potentially via auth bridge
  def url_for_with_auth(business, request, path = '/', user_signed_in: false)
    return url_for(business, request, path) unless business
    
    # If user is signed in on main domain and business uses custom domain,
    # route through auth bridge to transfer session
    if user_signed_in && 
       business.host_type_custom_domain? && 
       business.custom_domain_allow? &&
       main_domain?(request.host)
      
      target_url = url_for(business, request, path)
      # Include business ID for target URL validation security
      # Use consistent parameter order for tests
      query_string = "target_url=#{CGI.escape(target_url)}&business_id=#{business.id}"
      main_domain_url_for(request, "/auth/bridge?#{query_string}")
    else
      # Direct link for subdomains or when user not signed in
      url_for(business, request, path)
    end
  end
end
