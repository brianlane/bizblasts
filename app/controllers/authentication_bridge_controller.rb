class AuthenticationBridgeController < ApplicationController
  # Skip tenant requirement for this controller since we're bridging across domains
  skip_before_action :set_tenant
  skip_before_action :authenticate_user!, only: [:consume, :consume_token]

  # Enforce main-domain restriction only for bridge creation
  # Token consumption happens on the *custom* domain, so we only restrict the create action
  before_action :ensure_main_domain, only: [:create]

  # Enforce custom-domain restriction for reverse bridge (custom → main)
  before_action :ensure_custom_domain, only: [:bridge_to_main]

  # Specs expect rate-limiting behaviour to be enforced even in the test
  # environment, so we no longer skip the callback when Rails.env.test?
  before_action :rate_limit_user, only: [:create]
  
  # Generate authentication bridge token for authenticated user
  # GET /auth/bridge?target_url=https://custom-domain.com/path&business_id=123
  def create
    unless user_signed_in?
      AuthenticationTracker.track_bridge_failed('unauthenticated', request)
      Rails.logger.warn "[AuthBridge] Unauthenticated access attempt from #{request.remote_ip}"
      render json: { error: 'Authentication required' }, status: :unauthorized
      return
    end

    # Enhanced security: Check for suspicious request patterns
    unless valid_bridge_request?
      AuthenticationTracker.track_suspicious_request(request, 'invalid_bridge_request', user: current_user)
      Rails.logger.warn "[AuthBridge] Suspicious request pattern from user #{current_user.id}, IP: #{request.remote_ip}"
      render json: { error: 'Invalid request' }, status: :bad_request
      return
    end

    target_url = params[:target_url]
    business_id = params[:business_id]

    # -----------------------------------------------------------------
    # Validate business presence and type *before* validating the URL so we
    # can provide more specific error feedback expected by specs (and users)
    # -----------------------------------------------------------------
    if business_id.blank?
      Rails.logger.warn "[AuthBridge] Missing business_id for bridge request"
      render json: { error: 'business_id is required' }, status: :bad_request
      return
    end

    business = Business.find_by(id: business_id)
    unless business
      Rails.logger.warn "[AuthBridge] Unknown business_id #{business_id}"
      render json: { error: 'Unknown business' }, status: :not_found
      return
    end

    unless business.host_type_custom_domain?
      Rails.logger.warn "[AuthBridge] Business #{business_id} is not custom domain type"
      render json: { error: 'Business is not custom domain type' }, status: :bad_request
      return
    end

    # -----------------------------------------------------------------
    # Validate the target URL now that we know the business is eligible. This
    # runs *after* the custom-domain check so the error message above takes
    # precedence when appropriate.
    # -----------------------------------------------------------------
    unless valid_target_url?(target_url, business_id)
      AuthenticationTracker.track_bridge_failed('invalid_target_url', request, user: current_user, target_url: target_url, business_id: business_id)
      Rails.logger.warn "[AuthBridge] Invalid target URL from user #{current_user.id}: #{target_url&.truncate(100)}"
      render json: { error: 'Invalid target URL' }, status: :bad_request
      return
    end
    
    begin
      # Validate target URL before processing
      if target_url.length > 2000
        render json: { error: 'Target URL too long' }, status: :bad_request
        return
      end
      
      # Parse and validate target URL
      begin
        uri = URI.parse(target_url)
      rescue URI::InvalidURIError => e
        Rails.logger.warn "[AuthBridge] Invalid target URL: [FILTERED] - #{e.message}"
        render json: { error: 'Invalid target URL' }, status: :bad_request
        return
      end

      # Require business_id and validate host matches business canonical domain
      # This block is now redundant as business is loaded and validated earlier
      # unless business_id.present?
      #   Rails.logger.warn "[AuthBridge] Missing business_id for bridge request"
      #   render json: { error: 'business_id is required' }, status: :bad_request
      #   return
      # end

      # business = Business.find_by(id: business_id)
      # unless business
      #   Rails.logger.warn "[AuthBridge] Unknown business_id #{business_id}"
      #   render json: { error: 'Unknown business' }, status: :not_found
      #   return
      # end

      canonical_host = business.canonical_domain.presence || business.hostname
      unless canonical_host.present?
        Rails.logger.warn "[AuthBridge] Business #{business_id} has no canonical host configured"
        render json: { error: 'Business not configured for bridge' }, status: :unprocessable_entity
        return
      end

      request_host = uri.host.to_s.downcase
      target_apex = request_host.sub(/^www\./, '')
      canonical_apex = canonical_host.downcase.sub(/^www\./, '')
      unless target_apex == canonical_apex
        Rails.logger.warn "[AuthBridge] Rejected target host #{request_host} for business #{business_id} (expected #{canonical_host})"
        render json: { error: 'Target host does not match business domain' }, status: :forbidden
        return
      end
      
        # Create database-backed auth token (short-lived, secure)
        auth_token = AuthToken.create_for_user!(
          current_user,
          target_url,
          request
        )

        # Track successful token creation
        AuthenticationTracker.track_bridge_created(current_user, target_url, business_id, request)

      # Build redirect URL to custom domain's token consumption endpoint
      # This avoids embedding tokens in query params for better security

      # Route to the token consumption endpoint on the canonical target domain
      # Use the business canonical host to avoid apex↔www 301 hops
      canonical_host_for_redirect = canonical_host
      consumption_url = "#{uri.scheme}://#{canonical_host_for_redirect}"
      consumption_url += ":#{uri.port}" if uri.port && ![80, 443].include?(uri.port)
      consumption_url += "/auth/consume?auth_token=#{CGI.escape(auth_token.token)}"

      # Preserve the original target path for after authentication
      if uri.path.present? && uri.path != '/'
        consumption_url += "&redirect_to=#{CGI.escape(uri.path)}"
      end

      # Preserve query parameters from original URL
      if uri.query.present?
        consumption_url += "&original_query=#{CGI.escape(uri.query)}"
      end

      Rails.logger.info "[AuthBridge] Created auth token for user #{current_user.id}, redirecting to #{uri.host}"
      
      redirect_to consumption_url, allow_other_host: true
      
    rescue => e
      Rails.logger.error "[AuthBridge] Failed to create bridge: #{e.message}"
      render json: { error: 'Failed to create authentication bridge' }, status: :internal_server_error
    end
  end
  
  # Consume authentication bridge token and sign in user on custom domain
  # GET /auth/consume?auth_token=xyz&redirect_to=/path&original_query=param1=value1
  def consume_token
    token = params[:auth_token]
    
    unless token.present?
      Rails.logger.warn "[AuthBridge] Token consumption attempted without token from #{request.remote_ip}"
      redirect_to '/', alert: 'Authentication token required'
      return
    end
    
    begin
      # Prevent caching of token-bearing responses
      response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, private'
      response.headers['Pragma'] = 'no-cache'
      response.headers['Expires'] = '0'
      # Consume the database-backed token
      auth_token = AuthToken.consume!(token, request)
      
      unless auth_token
        AuthenticationTracker.track_bridge_failed('invalid_token', request, token: token&.first(8))
        Rails.logger.warn "[AuthBridge] Invalid or expired token attempted from #{SecurityConfig.client_ip(request)}"
        redirect_to '/', alert: 'Invalid or expired authentication token'
        return
      end

      # Track successful token consumption
      AuthenticationTracker.track_bridge_consumed(auth_token.user, auth_token, request)

      # Sign in the user on this domain
      sign_in(auth_token.user)
      # Rotate session token for extra security and set in session
      auth_token.user.rotate_session_token!
      session[:session_token] = auth_token.user.session_token

      Rails.logger.info "[AuthBridge] Successfully authenticated user #{auth_token.user.id} on custom domain #{request.host}"
      
      # Remove any legacy session cookies that might shadow the new host-only cookie
      # Browsers can send multiple cookies with the same name (e.g., Domain=.newcoworker.com and host-only
      # for www.newcoworker.com). Rack may pick the wrong one, making the request look anonymous.
      begin
        session_key = Rails.application.config.session_options[:key] || '_session_id'
        base_root   = request.host.sub(/^www\./, '')
        # Expire broader-domain cookies
        cookies.delete(session_key, domain: ".#{base_root}", path: '/')
        cookies.delete(session_key, domain: base_root, path: '/')
        # Also expire a mis-set cookie on the exact host with an explicit Domain attribute
        cookies.delete(session_key, domain: request.host, path: '/')
      rescue => e
        Rails.logger.debug "[AuthBridge] Cookie cleanup skipped: #{e.message}"
      end

      # Build the final redirect URL from the consumed token's target_url and preserved parameters
      # Also include any additional query parameters that came directly in this request
      # Only permit safe tracking/analytics parameters to prevent security issues
      additional_params = params.except(:auth_token, :redirect_to, :original_query, :controller, :action)
                                .permit(:utm_source, :utm_medium, :utm_campaign, :utm_term, :utm_content, 
                                       :ref, :source, :medium, :campaign, :gclid, :fbclid)
      additional_query = additional_params.present? ? additional_params.to_query : nil
      
      # Build the final redirect URL from the token's target_url and preserved parameters
      # Extract path and query from target_url to avoid duplicates
      redirect_path = build_redirect_from_target_url(auth_token.target_url, params[:original_query], additional_query)
      
      # Redirect to the final destination with a success message
      Rails.logger.info "[AuthBridge] Token target_url: #{auth_token.target_url}, final redirect_path: #{redirect_path}"
      redirect_to redirect_path, notice: 'Successfully signed in', allow_other_host: true
      
    rescue => e
      Rails.logger.error "[AuthBridge] Failed to consume token: #{e.message}"
      redirect_to '/', alert: 'Authentication failed'
    end
  end
  
  # Legacy consume method for backward compatibility (if needed)
  # POST /auth/bridge/consume
  def consume
    token = params[:auth_token]
    
    unless token.present?
      render json: { error: 'Token required' }, status: :bad_request
      return
    end
    
    begin
      bridge = AuthenticationBridge.consume_token!(token, request.remote_ip)
      
      unless bridge
        Rails.logger.warn "[AuthBridge] Invalid or expired token attempted from #{request.remote_ip}"
        render json: { error: 'Invalid or expired token' }, status: :unauthorized
        return
      end
      
      # Sign in the user on this domain
      sign_in(bridge.user)
      # Rotate session token for extra security and set in session
      bridge.user.rotate_session_token!
      session[:session_token] = bridge.user.session_token

      Rails.logger.info "[AuthBridge] Successfully bridged authentication for user #{bridge.user.id} from #{request.remote_ip}"
      
      render json: { 
        success: true, 
        user_id: bridge.user.id,
        redirect_url: bridge.target_url 
      }
      
    rescue => e
      Rails.logger.error "[AuthBridge] Failed to consume token: #{e.message}"
      render json: { error: 'Failed to process authentication' }, status: :internal_server_error
    end
  end
  
  # Health check endpoint for authentication bridge
  def health
    render json: {
      status: 'ok',
      environment: Rails.env,
      main_domain: main_domain_request?
    }
  end

  # Reverse bridge: custom domain → main domain
  # GET /auth/bridge_to_main?target_path=/dashboard
  def bridge_to_main
    unless user_signed_in?
      Rails.logger.warn "[AuthBridge] Unauthenticated reverse bridge attempt from #{request.remote_ip}"
      # Redirect to sign in on current domain, then redirect back here
      session[:return_to] = request.fullpath
      redirect_to new_user_session_path
      return
    end

    # Determine main domain based on environment
    main_domain = if Rails.env.production?
      'https://bizblasts.com'
    elsif Rails.env.development?
      "#{request.protocol}lvh.me:#{request.port}"
    else
      # Test environment
      "#{request.protocol}example.com"
    end

    # Get target path (default to root)
    target_path = params[:target_path].presence || '/'

    # Sanitize target path
    target_path = sanitize_redirect_path(target_path)

    # Build full target URL
    target_url = "#{main_domain}#{target_path}"

    # Validate target URL
    unless valid_main_domain_target?(target_url)
      Rails.logger.warn "[AuthBridge] Invalid main domain target: #{target_url}"
      redirect_to '/', alert: 'Invalid target destination'
      return
    end

    begin
      # Create auth token for main domain
      auth_token = AuthToken.create_for_user!(
        current_user,
        target_url,
        request
      )

      # Track the reverse bridge creation
      AuthenticationTracker.track_event(
        :reverse_bridge_created,
        user: current_user,
        request: request,
        target_url: target_url
      )

      # Build consumption URL on main domain
      consumption_url = "#{main_domain}/auth/consume?auth_token=#{CGI.escape(auth_token.token)}"

      # Preserve target path
      if target_path.present? && target_path != '/'
        consumption_url += "&redirect_to=#{CGI.escape(target_path)}"
      end

      Rails.logger.info "[AuthBridge] Reverse bridge created for user #{current_user.id}, redirecting to main domain"

      # Redirect to main domain with auth token
      redirect_to consumption_url, allow_other_host: true

    rescue => e
      Rails.logger.error "[AuthBridge] Failed to create reverse bridge: #{e.message}"
      redirect_to '/', alert: 'Failed to authenticate on main domain'
    end
  end

  private
  
  def ensure_main_domain
    unless main_domain_request?
      render json: { error: 'This endpoint is only available on the main domain' }, status: :forbidden
    end
  end

  def ensure_custom_domain
    # Only allow reverse bridge from custom domains
    # This prevents users from creating unnecessary tokens when already on main domain
    if main_domain_request?
      Rails.logger.debug "[AuthBridge] Reverse bridge attempted from main domain, redirecting directly"
      # If they're on main domain, just redirect to target path directly
      target_path = params[:target_path].presence || '/'
      redirect_to target_path
      return
    end
  end

  def valid_main_domain_target?(url)
    return false unless url.present?

    begin
      uri = URI.parse(url)

      # Must have valid host
      return false unless uri.host.present?

      # Verify it's actually a main domain URL
      main_domain_hosts = if Rails.env.production?
        ['bizblasts.com', 'www.bizblasts.com']
      elsif Rails.env.development?
        ['lvh.me', 'www.lvh.me', 'localhost']
      else
        ['example.com', 'www.example.com', 'test.host']
      end

      return false unless main_domain_hosts.include?(uri.host&.downcase)

      # Path should be safe
      return false if uri.path.include?('../')

      true
    rescue URI::InvalidURIError
      false
    end
  end
  
  def build_redirect_from_target_url(target_url, original_query, additional_query = nil)
    return '/' unless target_url.present?

    # SECURITY: Always sanitize the full target URL first. This method enforces
    # same-host policy, strips dangerous characters, validates traversal, etc.
    sanitized = sanitize_redirect_path(target_url)

    # If sanitize_redirect_path rejected or normalized to root, keep it
    return sanitized if sanitized == '/'

    # Split sanitized result into path and existing query
    base_path, existing_query = sanitized.split('?', 2)

    # Merge queries with deduplication. Order of precedence (last wins):
    # 1) existing query from sanitized target_url
    # 2) original_query preserved from bridge creation
    # 3) additional_query from current request
    merged_query = merge_query_parameters(existing_query, original_query, additional_query)

    merged_query.present? ? "#{base_path}?#{merged_query}" : base_path
  end
  
  def merge_query_parameters(*query_strings)
    # Merge multiple query strings, with later ones taking precedence for duplicate keys
    merged_params = {}
    
    query_strings.compact.each do |query_string|
      next unless query_string.present?
      
      sanitized_query = sanitize_query_string(query_string)
      next unless sanitized_query.present?
      
      # Parse query string into key-value pairs
      begin
        URI.decode_www_form(sanitized_query).each do |key, value|
          merged_params[key] = value
        end
      rescue ArgumentError => e
        Rails.logger.warn "[AuthBridge] Invalid query string: #{query_string} - #{e.message}"
      end
    end
    
    # Convert back to query string
    merged_params.any? ? URI.encode_www_form(merged_params) : nil
  end

  def build_final_redirect_path(redirect_to, original_query, additional_query = nil)
    # Sanitize redirect path to prevent open redirects
    path = sanitize_redirect_path(redirect_to)
    
    # Collect all query parameters
    query_parts = []
    
    # Add original query parameters if they exist
    if original_query.present?
      # Sanitize query parameters
      sanitized_query = sanitize_query_string(original_query)
      query_parts << sanitized_query if sanitized_query.present?
    end
    
    # Add additional query parameters if they exist
    if additional_query.present?
      sanitized_additional = sanitize_query_string(additional_query)
      query_parts << sanitized_additional if sanitized_additional.present?
    end
    
    # Combine all query parts
    if query_parts.any?
      separator = path.include?('?') ? '&' : '?'
      path = "#{path}#{separator}#{query_parts.join('&')}"
    end
    
    path
  end
  
  def sanitize_redirect_path(redirect_to)
    return '/' unless redirect_to.present?
    
    begin
      # Parse as URI to validate structure
      uri = URI.parse(redirect_to)
      
      # For absolute URLs, only allow same host to prevent open redirects
      if uri.scheme.present? || uri.host.present?
        # Allow URLs to the same domain (ignoring subdomains) as the current request
        current_domain = request.host.sub(/^www\./, '')
        target_domain = uri.host.sub(/^www\./, '')
        
        Rails.logger.debug "[AuthBridge] Domain comparison - current: #{current_domain}, target: #{target_domain}, request.host: #{request.host}, uri.host: #{uri.host}"
        
        if target_domain != current_domain
          Rails.logger.warn "[AuthBridge] Rejected cross-domain redirect: #{redirect_to} (current domain: #{current_domain}, target domain: #{target_domain})"
          return '/'
        end
        
        # For same-host absolute URLs, return the path with query
        result = uri.path.presence || '/'
        result += "?#{uri.query}" if uri.query.present?
        return result
      end
      
      # Ensure path starts with /
      path = uri.path
      path = "/#{path}" unless path.start_with?('/')

      # Remove any dangerous characters or patterns from path
      path = path.gsub(/[<>'"&]/, '')

      # Validate path doesn't contain directory traversal
      if path.include?('../') || path.include?('..\\')
        Rails.logger.warn "[AuthBridge] Rejected path traversal attempt: #{redirect_to}"
        return '/'
      end

      # Preserve and sanitize query string for relative URLs
      full_path = path
      if uri.query.present?
        sanitized_query = sanitize_query_string(uri.query)
        full_path = sanitized_query.present? ? "#{path}?#{sanitized_query}" : path
      end

      # Limit path length (including query)
      if full_path.length > 2000
        Rails.logger.warn "[AuthBridge] Rejected overly long path: #{full_path.length} chars"
        return '/'
      end

      full_path
      
    rescue URI::InvalidURIError => e
      Rails.logger.warn "[AuthBridge] Invalid redirect_to URI: #{redirect_to} - #{e.message}"
      '/'
    end
  end
  
  def sanitize_query_string(query)
    return nil unless query.present?
    
    begin
      # Parse query string
      params = CGI.parse(query)
      
      # Remove potentially dangerous parameters
      dangerous_params = %w[auth_token token session_id csrf_token]
      params = params.reject { |key, _| dangerous_params.include?(key.downcase) }
      
      # Rebuild query string with sanitized values
      sanitized_params = params.map do |key, values|
        # Sanitize key and values
        clean_key = CGI.escape(key.to_s.gsub(/[<>'"&]/, ''))
        clean_values = values.map { |v| CGI.escape(v.to_s.gsub(/[<>'"&]/, '')) }
        clean_values.map { |v| "#{clean_key}=#{v}" }
      end.flatten
      
      sanitized_params.join('&')
      
    rescue => e
      Rails.logger.warn "[AuthBridge] Error sanitizing query: #{query} - #{e.message}"
      nil
    end
  end
  
  def valid_target_url?(url, business_id = nil)
    return false unless url.present?
    
    begin
      uri = URI.parse(url)
      
      # Must be HTTPS in production
      if Rails.env.production? && uri.scheme != 'https'
        Rails.logger.warn "[AuthBridge] Rejected non-HTTPS URL in production: #{uri.scheme}"
        return false
      end
      
      # Must have a valid host
      return false unless uri.host.present?
      
      # Don't allow redirecting to the main domain (infinite loop prevention)
      main_domains = ['bizblasts.com', 'www.bizblasts.com']
      if Rails.env.production? && main_domains.include?(uri.host)
        Rails.logger.warn "[AuthBridge] Rejected redirect to main domain: #{uri.host}"
        return false
      end
      
      # In development and test, allow localhost and lvh.me without business validation
      if Rails.env.development? || Rails.env.test?
        allowed_patterns = [
          /localhost/,
          /127\.0\.0\.1/,
          /\.lvh\.me$/,
          /lvh\.me$/,
          /example\.com$/,  # Test environment
          /test\.host$/     # RSpec default
        ]
        return true if allowed_patterns.any? { |pattern| uri.host =~ pattern }
      end
      
      # Business ID validation - ensure target URL belongs to specified business
      if business_id.present?
        business = Business.find_by(id: business_id)
        unless business
          Rails.logger.warn "[AuthBridge] Business not found: #{business_id}"
          return false
        end
        
        # Must be a custom domain business
        unless business.host_type_custom_domain?
          Rails.logger.warn "[AuthBridge] Business #{business_id} is not custom domain type"
          return false
        end
        
        # Must be active
        unless business.custom_domain_allow?
          Rails.logger.warn "[AuthBridge] Business #{business_id} custom domain not allowed"
          return false
        end
        
        # Target URL host must match the business’ canonical preference (apex vs www)
        allowed_hosts = begin
          canonical = business.canonical_domain.presence || business.hostname
          apex      = canonical.sub(/^www\./, '')
          [apex, "www.#{apex}"].map(&:downcase)
        end

        unless allowed_hosts.include?(uri.host.to_s.downcase)
          Rails.logger.warn "[AuthBridge] Target URL host #{uri.host} doesn't match business allowed hosts #{allowed_hosts.join(', ')}"
          return false
        end
        
        Rails.logger.debug "[AuthBridge] Target URL validated for business #{business_id}: #{uri.host}"
        return true
      end
      
      # Fallback: Must be a custom domain we recognize (for legacy compatibility)
      custom_domain_business = Business.find_by(
        hostname: uri.host,
        host_type: 'custom_domain',
        status: 'cname_active'
      )
      
      if custom_domain_business.present?
        Rails.logger.debug "[AuthBridge] Target URL validated via fallback lookup: #{uri.host}"
        return true
      else
        Rails.logger.warn "[AuthBridge] Unknown custom domain: #{uri.host}"
        return false
      end
      
    rescue URI::InvalidURIError => e
      Rails.logger.warn "[AuthBridge] Invalid URI: #{url} - #{e.message}"
      false
    end
  end
  
  def rate_limit_user
    # Determine an identifier for rate-limiting. If the user is authenticated and present,
    # we use their user ID to prevent them from exhausting the quota via multiple IPs.
    # Otherwise we fall back to the request IP so anonymous traffic is also throttled.
    identifier =
      begin
        if respond_to?(:user_signed_in?) && user_signed_in? && current_user.present?
          "user:#{current_user.id}"
        else
          "ip:#{request.remote_ip}"
        end
      rescue Devise::MissingWarden
        # In cases where Warden middleware is unavailable (e.g. during certain specs)
        # we still want to apply IP-based throttling.
        "ip:#{request.remote_ip}"
      end

    # Simple rate limiting: max 10 bridge attempts per identifier per hour (5 in test).
    cache_key = "auth_bridge_rate_limit:#{identifier}"
    attempts  = Rails.cache.read(cache_key) || 0
    limit     = Rails.env.test? ? 5 : 10

    if attempts >= limit
      AuthenticationTracker.track_event(
        :bridge_rate_limited,
        user: current_user,
        request: request,
        attempts: attempts,
        limit: limit,
        identifier: identifier
      )
      Rails.logger.warn "[AuthBridge] Rate limit exceeded for #{identifier}"
      render json: { error: 'Rate limit exceeded' }, status: :too_many_requests
      return
    end

    # Increment counter with a 1-hour expiry
    Rails.cache.write(cache_key, attempts + 1, expires_in: 1.hour)
  end
  
  # Enhanced security validation for auth bridge requests
  def valid_bridge_request?
    # Check for basic request validity
    return false unless request.get? || request.head?

    # Check for suspicious user agents (basic bot detection)
    if request.user_agent.present?
      user_agent = request.user_agent.downcase
      suspicious_patterns = [
        'bot', 'crawler', 'scraper', 'spider', 'scan',
        'curl', 'wget', 'postman', 'python-requests'
      ]

      if suspicious_patterns.any? { |pattern| user_agent.include?(pattern) }
        Rails.logger.debug "[AuthBridge] Suspicious user agent: #{request.user_agent}"
        return false
      end
    end

    # Check for rapid requests (additional to rate limiting)
    if detect_rapid_requests?
      Rails.logger.warn "[AuthBridge] Rapid requests detected from user #{current_user.id}"
      return false
    end

    # Check referrer validity (should come from our domains)
    unless valid_referrer?
      Rails.logger.debug "[AuthBridge] Invalid or missing referrer from user #{current_user.id}"
      # Don't reject based on referrer alone, but log for monitoring
    end

    true
  end

  # Detect rapid successive requests (beyond rate limiting)
  def detect_rapid_requests?
    # Only check for rapid requests if user is authenticated and Warden is available
    begin
      return false unless respond_to?(:user_signed_in?) && user_signed_in?
    rescue Devise::MissingWarden
      return false
    end

    cache_key = "auth_bridge_rapid_check:#{current_user.id}"
    last_request_time = Rails.cache.read(cache_key)
    current_time = Time.current

    if last_request_time && (current_time - last_request_time) < 2.seconds
      AuthenticationTracker.track_event(:rapid_requests, user: current_user, request: request,
                                       time_between_requests: (current_time - last_request_time).round(2))
      Rails.cache.write(cache_key, current_time, expires_in: 10.seconds)
      return true
    end

    Rails.cache.write(cache_key, current_time, expires_in: 10.seconds)
    false
  end

  # Validate referrer comes from expected domains
  def valid_referrer?
    return true unless request.referer.present? # Allow missing referrer

    begin
      referrer_uri = URI.parse(request.referer)
      expected_domains = if Rails.env.production?
        ['bizblasts.com', 'www.bizblasts.com']
      elsif Rails.env.development?
        ['lvh.me', 'www.lvh.me', 'localhost']
      else
        ['example.com', 'www.example.com', 'test.host']
      end

      expected_domains.include?(referrer_uri.host&.downcase)
    rescue URI::InvalidURIError
      false
    end
  end

  def main_domain_request?
    if Rails.env.development? || Rails.env.test?
      # Development/Test: Handle both lvh.me and example.com domains
      host = request.host.downcase
      main_domain_patterns = [
        'lvh.me',           # Development main domain
        'www.lvh.me',       # Development main domain with www
        'example.com',      # Test main domain
        'www.example.com',  # Test main domain with www (default in RSpec)
        'test.host',        # RSpec default host
        'localhost'         # Local development
      ]
      return true if main_domain_patterns.include?(host)

      # Also check for no subdomain or www subdomain on these domains
      host_parts = request.host.split('.')
      if host_parts.length >= 2
        base_domain = host_parts.last(2).join('.')
        if ['lvh.me', 'example.com', 'test.host'].include?(base_domain)
          # Only main domain if no subdomain or www subdomain
          return host_parts.length == 2 || (host_parts.length == 3 && host_parts.first == 'www')
        end
      end

      # For localhost or other single-part hosts in test, allow
      true
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
end