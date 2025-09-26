# frozen_string_literal: true

module Users
  # Custom sessions controller to handle redirection after sign-in
  # This controller extends Devise's SessionsController to provide:
  # 1. Cross-domain redirects for multi-tenant architecture
  # 2. Tenant-aware sign-in/sign-out behavior
  # 3. Dynamic domain support (subdomains and custom domains)
  # 4. Environment-aware URL generation (development vs production)
  class SessionsController < Devise::SessionsController
    # Redirect any new or create (sign-in) request that occurs on a tenant
    # subdomain or custom domain back to the platform’s main domain. All
    # authentication should be performed on the base domain to avoid cross-
    # domain cookie issues and for a consistent user experience.
    before_action :redirect_auth_from_subdomain, only: [:new, :create]
    
    # Skip tenant verification for sign out to allow proper cleanup
    # skip_before_action :set_tenant, only: :destroy # REMOVED: Global filter was removed
    
    # Skip CSRF verification for JSON requests during authentication
    # This is needed for API-based authentication flows
    skip_before_action :verify_authenticity_token, only: :create, if: -> { request.format.json? }

    # Override Devise's new method to handle already-signed-in users with cross-domain redirects
    # This prevents UnsafeRedirectError when users are already logged in and Devise tries to
    # redirect them without allow_other_host: true
    def new
      if user_signed_in?
        redirect_path = after_sign_in_path_for(current_user)
        Rails.logger.debug "[Sessions::new] User already signed in, redirecting to: #{redirect_path}"
        
        # Use allow_other_host: true to handle cross-domain redirects safely
        if redirect_path.include?("://") && redirect_path != request.url
          return redirect_to redirect_path, allow_other_host: true, status: :see_other
        else
          return redirect_to redirect_path, status: :see_other
        end
      end
      super
    end

    # Override Devise's create method to handle multi-tenant redirects
    # We need custom logic because Devise doesn't handle cross-domain redirects properly
    def create
      # We can't rely on super because it doesn't handle cross-domain redirects properly
      # Manual authentication using Warden
      self.resource = warden.authenticate!(auth_options)
      set_flash_message!(:notice, :signed_in)
      sign_in(resource_name, resource)
      
      # Store business ID in session if applicable (still useful for other potential logic)
      # This helps with performance and debugging by caching the business association
      if resource.respond_to?(:business) && resource.business.present?
        session[:business_id] = resource.business.id
      end
      
      # Get the redirect path manually rather than using respond_with
      # This gives us full control over where users go after sign-in
      redirect_path = after_sign_in_path_for(resource)
      
      # Use redirect_to with allow_other_host: true to handle cross-domain redirects
      # This is essential for multi-tenant architecture where users may be redirected
      # from the main site to their tenant's subdomain or custom domain
      if redirect_path.include?("://") && redirect_path != request.url
        Rails.logger.debug "[Sessions::create] Redirecting to external URL: #{redirect_path}"
        redirect_to redirect_path, allow_other_host: true, status: :see_other
      else
        Rails.logger.debug "[Sessions::create] Redirecting to internal path: #{redirect_path}"
        redirect_to redirect_path, status: :see_other
      end
    end
    
    # Override the path users are redirected to after sign in
    # This method handles three main scenarios:
    # 1. Business users (managers/staff) → Their tenant's management dashboard
    # 2. Users with stored locations → Previously visited page
    # 3. Everyone else → Root path
    def after_sign_in_path_for(resource)
      # ---------------------------------------------------------------------------
      # 0) Session-stored return_to (set during cross-domain redirect)
      # ---------------------------------------------------------------------------
      if session[:return_to].present?
        raw_target = session.delete(:return_to).to_s.strip

        sanitized_path = sanitize_return_to(raw_target)
        return sanitized_path if sanitized_path

        uri = begin
                URI.parse(raw_target)
              rescue URI::InvalidURIError
                nil
              end
        if uri && uri.host.present?
          if resource.is_a?(User) && resource.business.present?
            business = resource.business
            canonical = business.canonical_domain.presence || business.hostname
            apex      = canonical.sub(/^www\./,'').downcase
            allowed_hosts = [apex, "www.#{apex}"]

            if allowed_hosts.include?(uri.host.downcase)
              path_and_query = uri.path.presence || '/'
              path_and_query += "?#{uri.query}" if uri.query.present?
              return TenantHost.url_for_with_auth(
                business,
                request,
                path_and_query,
                user_signed_in: true
              )
            end
          end
        end
        # Fallback to role-based rules if unsafe
      end

      # ---------------------------------------------------------------------------
      # 0b) Explicit return_to param from login redirect (legacy support)
      # ---------------------------------------------------------------------------
      return_to_session = session.delete(:return_to)
      if return_to_session.present?
        sanitized = sanitize_return_to(return_to_session)
        return sanitized if sanitized
      end

      if params[:return_to].present?
        raw_target = params[:return_to].to_s.strip

        # -------------------------------------------------------------------
        # a) Accept *only* sanitized relative paths
        # -------------------------------------------------------------------
        sanitized_path = sanitize_return_to(raw_target)
        return sanitized_path if sanitized_path

        # -------------------------------------------------------------------
        # b) Accept absolute URLs only when host matches tenant domain
        # -------------------------------------------------------------------
        uri = begin
                URI.parse(raw_target)
              rescue URI::InvalidURIError
                nil
              end
        if uri && uri.host.present?
          if resource.is_a?(User) && resource.business.present?
            business = resource.business
            canonical = business.canonical_domain.presence || business.hostname
            apex      = canonical.sub(/^www\./,'').downcase
            allowed_hosts = [apex, "www.#{apex}"]

            if allowed_hosts.include?(uri.host.downcase)
              path_and_query = uri.path.presence || '/'
              path_and_query += "?#{uri.query}" if uri.query.present?
              return TenantHost.url_for_with_auth(
                business,
                request,
                path_and_query,
                user_signed_in: true
              )
            end
          end
        end
         
        # Fallback: ignore unsafe return_to and continue to role-based rules
      end

      # ---------------------------------------------------------------------------
      # 1) Business users (manager/staff) – redirect to dashboard
      # ---------------------------------------------------------------------------
      # Check if the user is a business user (manager or staff) and has an associated business
      if resource.is_a?(User) && resource.has_any_role?(:manager, :staff) && resource.business.present?
        Rails.logger.debug "[Sessions::after_sign_in] Business User: #{resource.email}. Redirecting to tenant dashboard."
        
        # Construct the URL for the tenant's dashboard based on the business setup
        # This handles both subdomain and custom domain configurations
        business = resource.business
        return TenantHost.url_for(business, request, '/manage/dashboard')
      end
      
      # Redirect clients to their dashboard
      if resource.is_a?(User) && resource.client?
        return dashboard_path
      end
      
      # Default Devise behavior or other roles (like client)
      # Stored location has precedence - this maintains user's intended destination
      stored_location = stored_location_for(resource)
      if stored_location
        Rails.logger.debug "[Sessions::after_sign_in] User: #{resource.email}. Redirecting to stored location: #{stored_location}."
        return stored_location
      end

      # Fallback to root path if no stored location
      # This is the default behavior for users without specific destinations
      Rails.logger.debug "[Sessions::after_sign_in] User: #{resource.email}. No stored location, redirecting to root_path."
      root_path
    end

    # Override Devise's destroy method to handle multi-tenant sign-out
    # This method needs to:
    # 1. Determine the current tenant context
    # 2. Clean up tenant-specific session data
    # 3. Clear cookies with the correct domain scope
    # 4. Redirect to the appropriate domain after sign-out
    def destroy
      # Check if we're on a subdomain or custom domain
      # This information is used to determine where to redirect after sign-out
      current_business = ActsAsTenant.current_tenant || find_current_business_from_request

      # Track where the request originated
      request_host = request.host.downcase

      # Was the request served from the business *custom* domain?
      @was_on_custom_domain = current_business&.host_type_custom_domain? && request_host == current_business.hostname.downcase

      # Was it served from the management *sub-domain* instead?
      @was_on_management_subdomain = current_business&.host_type_custom_domain? && request_host.ends_with?('.bizblasts.com')
      
      # Clear our custom cookies with environment-aware domain scoping
      # Cookies must be cleared with the same domain they were set with
      if Rails.env.development? || Rails.env.test?
        # Development: Always use .lvh.me for simplicity
        cookies.delete(:business_id, domain: '.lvh.me')
      else
        # Production: Use the appropriate domain based on business type
        if current_business&.host_type_custom_domain?
          # Always clear both the bizblasts cookie *and* the custom-domain cookies
          apex_domain = current_business.hostname.sub(/^www\./, '')
          session_key = Rails.application.config.session_options[:key] || :_session_id

          variants = [
            {},                                        # host-only cookie (no domain attribute)
            { domain: current_business.hostname },     # explicit host domain
            { domain: ".#{apex_domain}" },             # apex wildcard
            { domain: ".bizblasts.com" }               # management domain
          ]

          variants.each do |opts|
            cookies.delete(session_key, opts.merge(path: '/'))
            cookies.delete(:business_id, opts.merge(path: '/'))
          end
        else
          session_key = Rails.application.config.session_options[:key] || :_session_id
          cookies.delete(session_key, domain: '.bizblasts.com', path: '/')
          cookies.delete(:business_id, domain: '.bizblasts.com')
        end
      end
      
      # Clear tenant context using ActsAsTenant
      # This ensures no tenant-specific data remains in the session
      ActsAsTenant.current_tenant = nil
      
      # Call Devise's destroy method with custom redirect logic
      super do
        # Determine where to redirect after sign-out
        if @was_on_custom_domain
          redirect_url = determine_logout_redirect_url(current_business)
          Rails.logger.debug "[Sessions::destroy] Redirecting from custom domain to: #{redirect_url}"
          redirect_to redirect_url, allow_other_host: true and return
        elsif @was_on_management_subdomain
          # For management subdomains (bizblasts.com) of custom-domain tenants, bounce to platform main domain root.
          redirect_url = TenantHost.main_domain_url_for(request, '/')
          Rails.logger.debug "[Sessions::destroy] Redirecting management subdomain logout to main domain: #{redirect_url}"
          redirect_to redirect_url, allow_other_host: true and return
        elsif current_business&.host_type_subdomain?
          # Regular subdomain tenant – after logout go to platform main domain root
          redirect_url = TenantHost.main_domain_url_for(request, '/')
          Rails.logger.debug "[Sessions::destroy] Redirecting subdomain logout to main domain: #{redirect_url}"
          redirect_to redirect_url, allow_other_host: true and return
        else
          # User was on the main site, just go to root
          redirect_to root_path and return
        end
      end
    end

    private

    # -----------------------------------------------------------------------
    # Sanitizes a return_to string when it is meant to be a *relative* path.
    # Returns sanitized path or nil (when the string should be rejected).
    # Rules:
    #   • Must start with a single '/'
    #   • Must not start with '//'
    #   • Must not contain ':' before a '?'
    #   • Must not contain CR/LF characters (prevents injection)
    #   • Max length 2000
    # -----------------------------------------------------------------------
    def sanitize_return_to(raw)
      return nil unless raw.present?
      return nil if raw.length > 2000

      # Reject protocol-relative URLs (//example.com)
      return nil if raw.start_with?('//')

      # Allow only absolute paths beginning with '/'
      return nil unless raw.start_with?('/')

      # Reject CR/LF injection attempts
      return nil if raw.match?(/[\r\n]/)

      # Reject anything that looks like a scheme (e.g., 'javascript:') before the query string                                                                 
      path_part = raw.split('?',2).first
      return nil if path_part.include?(':')

      # Reject potentially dangerous characters and encode properly
      # Remove dangerous characters that could be used for injection
      sanitized = raw.gsub(/[<>"']/, '')
      # Remove control characters
      sanitized = sanitized.gsub(/[\u0000-\u001f\u007f-\u009f]/, '')
      
      # Additional validation: ensure it's a valid URI path
      begin
        # Use Addressable::URI for better unicode support, fallback to URI
        if defined?(Addressable::URI)
          uri = Addressable::URI.parse(sanitized)
          return sanitized if uri.scheme.nil? && sanitized.start_with?('/')
        else
          # Fallback: encode non-ASCII characters before parsing
          encoded = sanitized.encode('UTF-8').force_encoding('ASCII-8BIT').gsub(/[^\x00-\x7F]/n) { |char| 
            '%' + char.unpack('H2' * char.bytesize).join('%').upcase 
          }.force_encoding('UTF-8')
          uri = URI.parse(encoded)
          return sanitized if uri.scheme.nil? && sanitized.start_with?('/')
        end
      rescue => e
        # If parsing fails, but it's a simple path starting with '/', allow it
        return sanitized if sanitized.match?(/\A\/[^:]*\z/) && !sanitized.include?('//')
        return nil
      end

      sanitized
    end

    # Redirect sign-in requests that occur on a tenant host (subdomain or custom
    # domain) back to the platform’s base domain. This avoids cross-domain
    # cookie issues and keeps authentication UX consistent.
    def redirect_auth_from_subdomain
      return if TenantHost.main_domain?(request.host)

      # Preserve original full URL so we can send users back after authentication
      original_url = request.original_url
      session[:return_to] = original_url
      target_url = TenantHost.main_domain_url_for(
        request,
        "/users/sign_in"
      )
      Rails.logger.info "[Redirect Auth] Sign-in requested from tenant host; redirecting to #{target_url}"
      redirect_to target_url, status: :moved_permanently, allow_other_host: true and return
    end

    # Find the current business based on the request's hostname
    # This method handles both subdomain and custom domain scenarios
    # @return [Business, nil] The business associated with the current request
    def find_current_business_from_request
      # First, try to find by custom domain (exact hostname match)
      # Custom domains are stored as full hostnames in the database
      business = Business.find_by(host_type: 'custom_domain', hostname: request.host)
      return business if business

      # If no custom domain found, try to extract subdomain
      if Rails.env.development? || Rails.env.test?
        # Development: Use Rails' built-in subdomain method for lvh.me
        subdomain = request.subdomain
      else
        # Production: Manually extract subdomain from bizblasts.com requests
        # This is more reliable than Rails' subdomain method for custom setups
        host_parts = request.host.split('.')
        if host_parts.length >= 3 && host_parts.last(2).join('.') == 'bizblasts.com'
          subdomain = host_parts.first unless host_parts.first == 'www'
        end
      end
      
      # Look for business with matching subdomain
      if subdomain.present?
        Business.find_by(host_type: 'subdomain', hostname: subdomain)
      end
    end

    # Extract the main domain from a custom domain hostname
    # Example: app.mycompany.com → mycompany.com
    # @param custom_domain [String] The custom domain hostname
    # @return [String] The extracted main domain
    def extract_main_domain_from_custom_domain(custom_domain)
      parts = custom_domain.split('.')
      # Return the last two parts for most domains (handles .com, .co.uk, etc.)
      parts.length >= 2 ? parts.last(2).join('.') : custom_domain
    end

    # Determine where to redirect users after logout
    # This method considers the current business type and environment
    # @param business [Business, nil] The current business context
    # @return [String] The redirect URL after logout
    def determine_logout_redirect_url(business)
      if Rails.env.development? || Rails.env.test?
        # Development: Always redirect to lvh.me with current port
        "http://lvh.me:#{request.port}/"
      elsif business&.host_type_custom_domain?
        # Custom domain: Redirect to the main domain (not subdomain)
        # This provides a clean exit experience for custom domain users
        main_domain = extract_main_domain_from_custom_domain(business.hostname)
        "https://#{main_domain}/"
      else
        # Subdomain or unknown: Redirect to the main bizblasts.com site
        "https://bizblasts.com/"
      end
    end
  end
end