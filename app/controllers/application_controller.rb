# frozen_string_literal: true

# Main controller for the application that handles tenant setup, authentication,
# and error handling. Provides methods for maintenance mode and database connectivity checks.
class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include DatabaseErrorHandling
  include PolicyEnforcement
  
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Security: Verify allowed hosts to prevent CWE-20 (Incomplete URL Substring Sanitization)
  # This provides defense-in-depth against malicious domains bypassing client-side validation
  # Uses AllowedHostService for centralized domain validation
  before_action :verify_allowed_host!, unless: -> { maintenance_mode? }

  # Handle CSRF token issues for admin login after user logout
  before_action :handle_admin_csrf_token, if: -> { request.path == '/admin/login' && request.post? }

  # Redirect admin access attempts from subdomains to the main domain
  before_action :redirect_admin_from_subdomain
  
  # Handle CSRF token issues for admin actions when crossing domains (non-test environments only)
  before_action :handle_admin_csrf_for_actions, if: -> { 
    !Rails.env.test? && 
    request.path.start_with?('/admin') && 
    !request.get? && 
    request.path != '/admin/login' 
  }

  # Set current tenant based on subdomain/custom domain
  # This filter should be skipped in specific controllers where tenant context is handled differently
  before_action :set_tenant, unless: -> { maintenance_mode? }
  # (Removed obsolete redirect callback – route-level redirect now handles this)
  before_action :check_database_connection
  
  # Handle cross-domain authentication bridging (runs after tenant is set but before authentication)
  before_action :handle_cross_domain_authentication, unless: :skip_cross_domain_auth?

  # Check for blacklisted sessions before authentication
  before_action :check_session_blacklist, unless: :skip_user_authentication?

  # Authentication (now runs after tenant is set and cross-domain auth handling)
  before_action :authenticate_user!, unless: :skip_user_authentication?

  # Error handling for tenant not found
  rescue_from ActsAsTenant::Errors::NoTenantSet, with: :tenant_not_found

  # Handle Pundit NotAuthorizedError
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  
  # Handle unsafe redirect errors (e.g., when already-signed-in users access registration)
  rescue_from ActionController::Redirecting::UnsafeRedirectError, with: :handle_unsafe_redirect

  # Allow manually setting tenant in tests
  def self.allow_tenant_params
    # Used for testing - permits manually setting tenant in Devise controllers
    before_action :set_tenant_from_params, if: -> { Rails.env.test? && params[:tenant_id].present? }
  end

  # Authentication for ActiveAdmin - allows both AdminUser and User with admin role
  def authenticate_admin_user!
    # First try standard AdminUser authentication
    if admin_user_signed_in?
      return true
    end
    
    # Removed fallback to User with admin role
    
    # Otherwise redirect to login - use ActiveAdmin's login path if available
    redirect_to new_admin_user_session_path
  end

  # Helper method to check if admin user is signed in
  def admin_user_signed_in?
    warden.authenticated?(:admin_user)
  end

  # Helper method to get current admin user
  def current_admin_user
    # Removed fallback to User with admin role
    @current_admin_user ||= warden.authenticate(scope: :admin_user) if admin_user_signed_in?
  end

  # Fallback for serving ActiveAdmin assets directly if they're missing from the asset pipeline
  def self.serve_admin_assets
    Rails.application.routes.draw do
      # Direct file serving for admin assets as a last resort
      get '/assets/active_admin.css', to: proc { |env|
        file_path = Rails.root.join('public', 'assets', 'active_admin.css')
        if File.exist?(file_path)
          [200, {"Content-Type" => "text/css"}, [File.read(file_path)]]
        else
          [404, {"Content-Type" => "text/plain"}, ["Admin assets not found"]]
        end
      }, constraints: lambda { |req| req.format == :css }
    end
  end
  
  # Call the method to set up routes
  serve_admin_assets

  # Expose current tenant to controllers and views
  helper_method :current_tenant
  helper_method :allowed_asset_errors
  helper_method :asset_error_allowed?

  # Return the current ActsAsTenant tenant
  def current_tenant
    ActsAsTenant.current_tenant
  end

  # Allow certain asset errors to fail gracefully in test/development environments
  # This prevents tests from failing when assets aren't precompiled
  def allowed_asset_errors
    if Rails.env.test? || Rails.env.development?
      ['Sprockets::Rails::Helper::AssetNotFound', 'Sprockets::Rails::Helper::AssetNotPrecompiled']
    else
      []
    end
  end

  # Check if an error is an allowed asset error (including wrapped errors)
  def asset_error_allowed?(error)
    return false unless Rails.env.test? || Rails.env.development?

    # Check the error itself
    return true if error.class.name == 'Sprockets::Rails::Helper::AssetNotFound'

    # Check if it's a wrapped error with an asset error as the cause
    if error.respond_to?(:cause) && error.cause
      return true if error.cause.class.name == 'Sprockets::Rails::Helper::AssetNotFound'
    end

    # Check if the error message indicates an asset error
    return true if error.message&.include?('is not present in the asset pipeline')

    false
  end

  # Override Devise's current_user to validate session tokens
  def current_user
    # First get the user via Devise's standard mechanism
    user = super
    return nil unless user

    # Check server-side session blacklist first (immediate invalidation across all domains)
    if session[:session_token].present? && InvalidatedSession.session_blacklisted?(session[:session_token])
      AuthenticationTracker.track_event(:session_blacklisted, user: user, request: request,
                                       session_token: session[:session_token]&.first(8))
      Rails.logger.info "[current_user] Session blacklisted - user logged out elsewhere"
      sign_out(user)  # Properly clear Warden session and Rails session
      return nil
    end

    # If session token is present, validate it for global logout functionality
    # If not present (e.g., in tests or legacy sessions), allow the user through
    # This provides security when session tokens exist while maintaining compatibility
    if session[:session_token].present?
      unless user.valid_session?(session[:session_token])
        AuthenticationTracker.track_event(:session_invalidated, user: user, request: request,
                                         session_token: session[:session_token]&.first(8))
        Rails.logger.info "[current_user] Session token invalid - user logged out elsewhere"
        sign_out(user)  # Properly clear Warden session and Rails session
        return nil
      end
    end

    user
  end

  # Make tenant setting logic protected so subclasses can call it
  protected 

  # Enhanced tenant setting method that handles both subdomains and custom domains
  # This method now uses ActsAsTenant for consistent tenant handling
  def set_tenant
    # Don't override if tenant is already set
    return if ActsAsTenant.current_tenant.present?
    
    # Check if this is a main domain request (should not have tenant)
    if main_domain_request?
      Rails.logger.debug "[SetTenant] Main domain request detected, skipping tenant setup"
      ActsAsTenant.current_tenant = nil
      return
    end
    
    # Try to find business by custom domain first
    business = find_business_by_custom_domain
    
    # Custom domain redirects are handled by Render based on which domain was added as primary
    # No Rails-level redirects needed - Render automatically redirects to the canonical domain
    
    # If no custom domain match, try subdomain
    if business.nil?
      hostname = extract_hostname_for_tenant
      business = find_business_by_subdomain(hostname) if hostname.present?
    end
    
    # Set the tenant using ActsAsTenant if found
    if business
      ActsAsTenant.current_tenant = business
      Rails.logger.info "[SetTenant] Tenant set: Business ID #{business.id}"
      return
    end
    
    # Handle case where hostname/domain provided but no business found
    # Only show tenant_not_found if this looks like a subdomain request
    subdomain = request.subdomain
    
    if subdomain.present? && subdomain != 'www' && !main_domain_request?
      Rails.logger.warn "Tenant not found for hostname: #{subdomain}"
      tenant_not_found and return
    end
    
    # Session fallback logic for users who just signed up
    if user_signed_in? && session[:signed_up_business_id].present?
      fallback_business = Business.find_by(id: session[:signed_up_business_id])
      if fallback_business
        Business.set_current_tenant(fallback_business) # Use the Business model's method
        Rails.logger.info "Tenant set from session fallback: Business ID #{fallback_business.id}"
        # Consider clearing session after successful tenant switch
      else
        clear_tenant_and_log("Session fallback business ID not found: #{session[:signed_up_business_id]}")
        session.delete(:signed_up_business_id)
      end
      return
    end
    
    # Default case: No tenant context found
    clear_tenant_and_log("No specific tenant context found, clearing tenant.")
    ActsAsTenant.current_tenant = nil
  end

  # Helper to clear tenant and log - now uses ActsAsTenant
  def clear_tenant_and_log(message)
    Rails.logger.warn(message)
    ActsAsTenant.current_tenant = nil
  end

  # Check if businesses table exists (for handling migration scenarios)
  def businesses_table_exists?
    ActiveRecord::Base.connection.table_exists?('businesses')
  end

  # Find business by custom domain (exact hostname match)
  # Only allow active custom domains that are also health-verified to serve traffic
  def find_business_by_custom_domain
    return nil unless businesses_table_exists?

    host = request.host.to_s.downcase
    root = host.sub(/^www\./, '')
    candidates = [host, root, "www.#{root}"]

    Business.where(host_type: 'custom_domain', status: 'cname_active', domain_health_verified: true)
            .where('LOWER(hostname) IN (?)', candidates)
            .first
  end

  # Extract hostname/subdomain for tenant lookup
  def extract_hostname_for_tenant
    if Rails.env.development? || Rails.env.test?
      # Development: Use Rails' subdomain helper for lvh.me
      request.subdomain
    else
      # Production: Extract subdomain from bizblasts.com requests
      host_parts = request.host.split('.')
      
      # Handle standard bizblasts.com domains
      if host_parts.length >= 3 && host_parts.last(2).join('.') == 'bizblasts.com'
        first_part = host_parts.first
        return first_part unless first_part == 'www'
      end
      
      # Handle hosting platform scenarios (Render, Netlify, etc.)
      # Don't extract hostname from main domain patterns
      return nil if main_domain_request?
      
      # For custom domains or other scenarios, use the subdomain
      subdomain = request.subdomain
      return subdomain if subdomain.present? && subdomain != 'www'
      
      nil
    end
  end

  # Find business by subdomain
  def find_business_by_subdomain(hostname)
    return nil unless hostname.present? && businesses_table_exists?
    # Search for tenant businesses matching either hostname or subdomain (case-insensitive)
    Business.where("LOWER(hostname) = ? OR LOWER(subdomain) = ?", hostname.downcase, hostname.downcase)
            .first
  end

  # Legacy method - kept for compatibility but now uses ActsAsTenant directly
  def find_and_set_business_tenant(hostname)
    tenant = Business.find_by(hostname: hostname) || Business.find_by(subdomain: hostname)
    if tenant
      Business.set_current_tenant(tenant) # Use the Business model's method
      true
    else
      false
    end
  end

  def tenant_not_found
    @subdomain = request.subdomain || request.host
    render template: "errors/tenant_not_found", status: :not_found, layout: false
    false # Halt the filter chain
  end

  def set_tenant_from_params
    business = Business.find_by(id: params[:tenant_id])
    Business.set_current_tenant(business) if business
  end

  # Pundit authorization failure handler
  def user_not_authorized
    # Log security event for unauthorized access attempts
    SecureLogger.security_event('unauthorized_access', {
      user_id: current_user&.id,
      ip: request.remote_ip,
      path: request.fullpath,
      method: request.method
    })
    
    flash[:alert] = "You are not authorized to access this area."
    
    # For clients, redirect to their dashboard
    if user_signed_in? && current_user.client?
      redirect_to dashboard_path and return
    end
    
    # Otherwise redirect to root path
    redirect_to root_path, allow_other_host: true and return
  end

  def handle_unsafe_redirect
    # Log the unsafe redirect attempt for debugging
    Rails.logger.warn "[UnsafeRedirect] User #{current_user&.id || 'anonymous'} attempted unsafe redirect from #{request.fullpath}"
    
    # Render the standard Rails 404 page instead of showing Rails error
    render file: Rails.root.join('public', '404.html'), status: :not_found, layout: false
  end

  # === DEVISE OVERRIDES ===
  # Customize the redirect path after sign-in
  # This method now properly handles both subdomain and custom domain scenarios
  def after_sign_in_path_for(resource)
    # Check the type of resource signed in (User, AdminUser, etc.)
    if resource.is_a?(AdminUser)
      admin_root_path
    elsif resource.is_a?(User)
      case resource.role
      when 'manager', 'staff'
        # Redirect manager/staff to their business-specific dashboard
        # This logic handles both subdomain and custom domain cases
        if resource.business.present?
          redirect_url = generate_business_dashboard_url(resource.business)
          Rails.logger.debug "[after_sign_in] Manager/Staff redirecting to business dashboard"
          redirect_url
        else
          # Fallback if user has no business (should not happen for manager/staff)
          Rails.logger.warn "[after_sign_in] Manager/Staff user ##{resource.id} has no associated business."
          root_path
        end
      when 'client'
        # Redirect clients to the main client dashboard (on the main domain)
        dashboard_path
      else
        # Fallback for unknown roles
        root_path 
      end
    else
      # Default fallback for other resource types
      super
    end
  end


  # Generate the correct dashboard URL for a business (subdomain or custom domain)
  def generate_business_dashboard_url(business, path = '/manage/dashboard')
    # Use TenantHost for all URL generation - it handles all environments and edge cases
    TenantHost.url_for(business, request, path)
  end

  # Check for blacklisted sessions and redirect if necessary
  def check_session_blacklist
    # Get current user if available
    user = warden.user(:user) if respond_to?(:warden) && warden.present?
    return unless user

    # Check session token from session OR user's current session token
    session_token_to_check = session[:session_token].presence || user.session_token

    return unless session_token_to_check.present?

    # Check if session is blacklisted
    if InvalidatedSession.session_blacklisted?(session_token_to_check)
      # Track the event
      AuthenticationTracker.track_event(:session_blacklisted, user: user, request: request,
                                       session_token: session_token_to_check&.first(8))

      Rails.logger.info "[check_session_blacklist] Session blacklisted - redirecting to login"

      # Clear all session data including Warden
      sign_out(user)

      # Redirect to login
      redirect_to new_user_session_path and return
    end
  end

  # Keep other methods private
  private

  # Verify that the request host is allowed
  # Uses AllowedHostService to prevent CWE-20 (Incomplete URL Substring Sanitization)
  # This provides defense-in-depth against malicious domains like:
  # - evil-bizblasts.com (bypass via missing dot)
  # - mybizblasts.com.evil.org (bypass via domain in middle)
  def verify_allowed_host!
    unless AllowedHostService.allowed?(request.host)
      Rails.logger.warn "[Security] Blocked unauthorized host: #{request.host} from IP: #{request.remote_ip}"

      # Track security event
      # IMPORTANT: Do NOT call current_user here - this runs before set_tenant!
      # Calling current_user before tenant setup can cause session corruption
      # The request IP, host, and headers are sufficient for security tracking
      if defined?(AuthenticationTracker)
        AuthenticationTracker.track_suspicious_request(
          request,
          "unauthorized_host: #{request.host}"
          # Note: user parameter intentionally omitted - tenant context not yet established
        )
      end

      # Return 400 Bad Request with generic message
      # Don't reveal why the request was rejected to prevent information disclosure
      head :bad_request
    end
  end

  def skip_user_authentication?
    # Skip authentication for:
    # 1. Devise controllers (login, registration, etc.)
    # 2. Admin (has its own authentication)
    # 3. Maintenance mode
    # 4. Public paths (everything except protected areas)

    return true if devise_controller?
    return true if request.path.start_with?('/admin')
    return true if maintenance_mode?

    # Default: Skip authentication UNLESS path requires it
    # This makes the app "public by default" with specific protected areas
    # Defense in depth: Controllers also have authenticate_user!, but this provides first-pass check
    !requires_authentication?
  end
  
  def skip_cross_domain_auth?
    # Skip cross-domain auth for these scenarios:
    devise_controller? ||                                    # Devise controllers handle their own auth
    request.path.start_with?('/admin') ||                   # Admin paths
    request.path.start_with?('/auth/bridge') ||             # Authentication bridge endpoints
    request.path.start_with?('/healthcheck') ||             # Health checks
    maintenance_mode? ||                                     # Maintenance mode
    main_domain_request?                                     # Already on main domain
    # Note: Removed user_signed_in? check - we WANT to attempt cross-domain auth when user is NOT signed in
  end
  
  # Handle cross-domain authentication bridging for custom domains
  def handle_cross_domain_authentication
    # Only process for custom domains
    return unless on_custom_domain?
    
    # If user is already signed in, no need for cross-domain auth
    return if user_signed_in?
    
    # Debug logging
    Rails.logger.info "[CrossDomainAuth] Processing custom domain: #{request.host}, path: #{request.path}, referrer: #{request.referer}"
    
    # Check if we have an auth token to consume (session restoration)
    auth_token = params[:auth_token]
    if auth_token.present?
      Rails.logger.info "[CrossDomainAuth] Found auth token, attempting to consume"
      consume_auth_token(auth_token)
      return
    end
    
    # For session restoration, attempt if user likely came from main domain
    # This uses a blocking redirect approach with tokens, not iframe
    if should_attempt_session_restoration?
      Rails.logger.info "[CrossDomainAuth] Should attempt session restoration, redirecting to bridge"
      redirect_to_auth_bridge
      return
    else
      Rails.logger.info "[CrossDomainAuth] Not attempting session restoration - likely_cross_domain_user?: #{likely_cross_domain_user?}"
    end

    # Even if we don't attempt session restoration, we still need to redirect
    # unauthenticated users to the auth bridge for protected paths
    if requires_authentication?
      Rails.logger.info "[CrossDomainAuth] Protected path detected, redirecting unauthenticated user to bridge"
      redirect_to_auth_bridge
      return
    end
  end
  
  # Helper method for consistent business context detection across all controllers
  # Use this method only AFTER tenant has been set (in controller actions)
  def on_business_domain?
    !main_domain_request? && ActsAsTenant.current_tenant.present?
  end

  # Helper method for before_action conditions (before tenant is set)
  # This doesn't rely on ActsAsTenant.current_tenant being set yet
  def before_action_business_domain_check
    !main_domain_request?
  end

  private

  def on_custom_domain?
    return false if main_domain_request?
    
    # We're on a custom domain if we found a business by custom domain lookup
    current_business = ActsAsTenant.current_tenant
    current_business&.host_type == 'custom_domain'
  end
  
  def consume_auth_token(token)
    begin
      # Consume database-backed AuthToken
      auth_token = AuthToken.consume!(token, request)
      
      if auth_token
        # Successfully consumed token, sign in the user
        sign_in(auth_token.user)
        Rails.logger.info "[CrossDomainAuth] Successfully authenticated user #{auth_token.user.id} via auth bridge token"
        
        # Redirect to clean URL (remove auth_token parameter)
        # Fix: Properly handle auth_token removal regardless of position
        uri = URI.parse(request.url)
        if uri.query
          # Parse query parameters and remove auth_token
          query_params = CGI.parse(uri.query)
          query_params.delete('auth_token')
          
          # Rebuild query string
          if query_params.empty?
            uri.query = nil
          else
            # Convert back to query string format (CGI.parse creates arrays, so flatten single values)
            clean_params = query_params.map do |key, values|
              values.map { |value| "#{CGI.escape(key)}=#{CGI.escape(value)}" }
            end.flatten
            uri.query = clean_params.join('&')
          end
        end
        clean_url = uri.to_s
        redirect_to clean_url and return
      else
        Rails.logger.warn "[CrossDomainAuth] Invalid or expired auth token from #{request.remote_ip}"
      end
    rescue => e
      Rails.logger.error "[CrossDomainAuth] Failed to consume auth token: #{e.message}"
    end
  end
  
  def should_attempt_session_restoration?
    # Only attempt for GET and HEAD requests
    return false unless (request.get? || request.head?)

    # Skip for asset files and system endpoints
    return false if skip_system_paths?

    # IMPORTANT: Only attempt session restoration for protected paths
    # This prevents unnecessary redirects for users viewing public content
    unless requires_authentication?
      Rails.logger.debug "[CrossDomainAuth] Public path detected, skipping session restoration"
      return false
    end

    # Multi-signal approach for session restoration detection
    # Use multiple indicators to determine if user likely has an active session
    restoration_signals = []

    # Signal 1: HTTP referrer from main domain
    if likely_cross_domain_user?
      restoration_signals << :referrer_from_main_domain
      Rails.logger.debug "[CrossDomainAuth] Signal detected: referrer_from_main_domain"
    end

    # Signal 2: Recent auth activity for this business
    if current_tenant && recent_auth_bridge_activity?
      restoration_signals << :recent_auth_activity
      Rails.logger.debug "[CrossDomainAuth] Signal detected: recent_auth_activity"
    end

    # Signal 3: Authentication cookies present (even if expired)
    if auth_cookies_present?
      restoration_signals << :auth_cookies_present
      Rails.logger.debug "[CrossDomainAuth] Signal detected: auth_cookies_present"
    end

    # Signal 4: User agent suggests returning user (has session storage capabilities)
    if returning_user_agent?
      restoration_signals << :returning_user_agent
      Rails.logger.debug "[CrossDomainAuth] Signal detected: returning_user_agent"
    end

    # Attempt restoration if we have at least one strong signal
    should_attempt = restoration_signals.any?

    if should_attempt
      Rails.logger.info "[CrossDomainAuth] Session restoration signals: #{restoration_signals.join(', ')}"
    else
      Rails.logger.debug "[CrossDomainAuth] No session restoration signals detected"
    end

    should_attempt
  end

  def requires_authentication?
    # Check ALL request methods - authentication is required regardless of HTTP verb
    # Skip for asset files and system endpoints
    return false if skip_system_paths?

    # Simple approach: Only require authentication for protected paths
    # Everything else is public by default
    auth_required_paths = Rails.application.config.x.auth_required_paths

    # Defensive: Use sensible defaults if configuration is not loaded
    unless auth_required_paths.present?
      Rails.logger.warn "[Auth] auth_required_paths configuration missing, using fallback defaults"
      auth_required_paths = [
        '/manage', '/dashboard', '/admin', '/settings',
        '/profile', '/account', '/preferences', '/clients',
        '/my-bookings', '/invoices', '/transactions'
      ]
    end

    path = request.path.downcase
    auth_required_paths.any? { |pattern| path.start_with?(pattern) }
  end

  def skip_system_paths?
    skip_paths = [
      '/assets',             # Asset files
      '/favicon.ico',        # Favicon
      '/robots.txt',         # Robots.txt
      '/sitemap.xml',        # Sitemap
      '/healthcheck',        # Health checks
      '/up',                 # Rails up check
      '/maintenance',        # Maintenance page
      '/api'                 # API endpoints (exact match and with slash)
    ]

    path = request.path.downcase
    # Check for exact match or path starting with skip_path + '/'
    skip_paths.any? { |skip_path|
      path == skip_path || path.start_with?(skip_path + '/')
    }
  end
  
  def likely_cross_domain_user?
    # Check if this user likely came from the main domain and might be signed in
    
    # 1. Check HTTP referrer - if they came from main domain, likely signed in
    if request.referer.present?
      begin
        referrer_uri = URI.parse(request.referer)
        main_domains = if Rails.env.production?
          ['bizblasts.com', 'www.bizblasts.com']
        elsif Rails.env.development?
          ['lvh.me', 'www.lvh.me']
        else
          ['example.com', 'www.example.com']
        end
        
        return true if main_domains.include?(referrer_uri.host&.downcase)
      rescue URI::InvalidURIError
        # Invalid referrer, continue with other checks
      end
    end
    
    # 2. For public pages with no referrer info, don't attempt session restoration
    # This prevents unnecessary redirects for anonymous users who directly visit business pages
    # The main solution is to fix the business links to go through the auth bridge
    false
  end

  # Check for recent auth bridge activity for the current business
  def recent_auth_bridge_activity?
    return false unless current_tenant

    # Look for auth tokens created in the last 5 minutes for this business
    AuthToken.where(
      'created_at > ? AND target_url LIKE ?',
      5.minutes.ago,
      "%#{current_tenant.hostname}%"
    ).exists?
  rescue => e
    Rails.logger.debug "[CrossDomainAuth] Error checking recent auth activity: #{e.message}"
    false
  end

  # Check if authentication-related cookies are present
  def auth_cookies_present?
    # Check for any authentication-related cookies that might indicate a user session
    session_key = Rails.application.config.session_options[:key] || '_session_id'
    remember_token_key = 'remember_user_token'

    cookies[session_key].present? ||
    cookies[remember_token_key].present? ||
    cookies['_bizblasts_session'].present?
  rescue => e
    Rails.logger.debug "[CrossDomainAuth] Error checking auth cookies: #{e.message}"
    false
  end

  # Check if user agent suggests a returning user with session capabilities
  def returning_user_agent?
    return false unless request.user_agent.present?

    user_agent = request.user_agent.downcase

    # Skip obvious bots and crawlers
    bot_patterns = [
      'bot', 'crawler', 'spider', 'scraper', 'checker', 'monitor',
      'facebook', 'twitter', 'linkedin', 'google', 'bing', 'yahoo',
      'curl', 'wget', 'postman'
    ]

    return false if bot_patterns.any? { |pattern| user_agent.include?(pattern) }

    # Look for browsers that support modern session management
    browser_patterns = [
      'chrome', 'firefox', 'safari', 'edge', 'opera', 'brave'
    ]

    browser_patterns.any? { |pattern| user_agent.include?(pattern) }
  rescue => e
    Rails.logger.debug "[CrossDomainAuth] Error checking user agent: #{e.message}"
    false
  end
  

  def redirect_to_auth_bridge
    # Construct the bridge URL on the main domain
    # Fix: Always use the actual main domain, not the current request domain
    if Rails.env.production?
      main_domain = 'https://bizblasts.com'
    elsif Rails.env.development?
      # In development, use lvh.me as main domain
      main_domain = "#{request.protocol}lvh.me:#{request.port}"
    else
      # Test environment - use example.com as main domain
      main_domain = "#{request.protocol}example.com"
      main_domain += ":#{request.port}" if request.port && ![80, 443].include?(request.port)
    end
    
    target_url = request.url
    
    # Include business context for enhanced security validation
    bridge_params = { target_url: target_url }
    if current_tenant&.id
      bridge_params[:business_id] = current_tenant.id
    end
    
    bridge_url = "#{main_domain}/auth/bridge?#{bridge_params.to_query}"
    
    Rails.logger.info "[CrossDomainAuth] Redirecting to auth bridge: #{bridge_url}"
    redirect_to bridge_url, allow_other_host: true
  end

  def maintenance_mode?
    # Use this to whitelist certain paths during database issues
    maintenance_paths.include?(request.path)
  end

  def maintenance_paths
    ['/healthcheck', '/up', '/maintenance', '/db-check']
  end

  def check_database_connection
    # Skip in test/development environment or if path is whitelisted
    return if maintenance_mode? || Rails.env.test? || Rails.env.development?
    
    begin
      # Attempt a lightweight database query
      ActiveRecord::Base.connection.execute("SELECT 1")
    rescue ActiveRecord::ConnectionNotEstablished
      database_connection_error
    end
  end

  # Redirects requests to /admin from a subdomain to the main domain
  # Now handles both subdomain and custom domain scenarios
  def redirect_admin_from_subdomain
    # Check if it's an admin path and not on the main domain
    if request.path.start_with?('/admin')
      # Skip if already on main domain
      return if main_domain_request?
      
      # Construct the main domain URL
      main_domain_url = construct_main_domain_url
      
      Rails.logger.info "[Redirect Admin] Redirecting admin access to main domain"
      redirect_to main_domain_url, status: :moved_permanently, allow_other_host: true
    end
  end
  
  # Check if the current request is on the main domain
  def main_domain_request?
    if Rails.env.development? || Rails.env.test?
      # Development/Test: Handle both lvh.me and example.com domains
      host = request.host.downcase
      main_domain_patterns = [
        'lvh.me',           # Development main domain
        'www.lvh.me',       # Development main domain with www
        'example.com',      # Test main domain
        'www.example.com'   # Test main domain with www (default in RSpec)
      ]
      return true if main_domain_patterns.include?(host)
      
      # Also check for no subdomain or www subdomain on these domains
      host_parts = request.host.split('.')
      if host_parts.length >= 2
        base_domain = host_parts.last(2).join('.')
        if ['lvh.me', 'example.com'].include?(base_domain)
          # Only main domain if no subdomain or www subdomain
          return host_parts.length == 2 || (host_parts.length == 3 && host_parts.first == 'www')
        end
      end
      
      false
    else
      # Production: Check for actual main domain patterns
      host = request.host.downcase
      
      # Direct main domain patterns
      main_domain_patterns = [
        'bizblasts.com',
        'www.bizblasts.com',
        'bizblasts.onrender.com'  # Render's internal routing
      ]
      
      return true if main_domain_patterns.include?(host)
      
      # For bizblasts.com, only treat www or no subdomain as main domain
      host_parts = request.host.split('.')
      if host_parts.length >= 2 && host_parts.last(2).join('.') == 'bizblasts.com'
        # Only main domain if no subdomain or www subdomain
        return host_parts.length == 2 || (host_parts.length == 3 && host_parts.first == 'www')
      end
      
      false
    end
  end
  
  # Construct URL for the main domain preserving the current path
  def construct_main_domain_url
    if Rails.env.development? || Rails.env.test?
      main_domain_host = 'lvh.me'
    else
      main_domain_host = 'bizblasts.com'
    end
    
    port = request.port unless [80, 443].include?(request.port)
    port_str = port ? ":#{port}" : ""
    "#{request.protocol}#{main_domain_host}#{port_str}#{request.fullpath}"
  end

  # Handle CSRF token issues when logging into admin after user logout
  def handle_admin_csrf_token
    # Check if this is an admin login attempt with invalid CSRF token
    if params[:admin_user].present? && !verified_request?
      Rails.logger.warn "[CSRF Fix] Admin login attempt with invalid CSRF token, allowing request"
      # Skip CSRF verification for this request by regenerating the token
      session[:_csrf_token] = nil
      form_authenticity_token
    end
  end

  # Handle CSRF token issues for admin actions when crossing domains (production only)
  def handle_admin_csrf_for_actions
    # Check if this is an admin action with invalid CSRF token
    if !verified_request?
      Rails.logger.warn "[CSRF Fix] Admin action with invalid CSRF token: #{request.method} #{request.path}"
      Rails.logger.warn "[CSRF Fix] User Agent: #{request.user_agent&.truncate(50)}"
      Rails.logger.warn "[CSRF Fix] Referer: [REDACTED]"
      
      # Instead of silently fixing it, redirect to the admin dashboard to get a fresh session
      # This is safer than bypassing CSRF for all admin actions
      flash[:alert] = "Session expired. Please try your action again."
      redirect_to admin_root_path and return
    end
  end

  # Ensure all times are in the current tenant's local time zone
  around_action :use_business_time_zone

  # Wrap request in the tenant's time zone
  def use_business_time_zone(&block)
    # Ensure business has a valid time_zone populated
    if ActsAsTenant.current_tenant&.respond_to?(:ensure_time_zone!)
      ActsAsTenant.current_tenant.ensure_time_zone!
    end
    tz = ActsAsTenant.current_tenant&.time_zone.presence || 'UTC'
    Time.use_zone(tz, &block)
  end
end