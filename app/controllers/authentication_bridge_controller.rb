class AuthenticationBridgeController < ApplicationController
  # Skip tenant requirement for this controller since we're bridging across domains
  skip_before_action :set_tenant
  skip_before_action :authenticate_user!, only: [:consume, :consume_token]
  
  # Enforce main-domain restriction only for bridge creation
  # Token consumption happens on the *custom* domain, so we only restrict the create action
  before_action :ensure_main_domain, only: [:create]

  # Specs expect rate-limiting behaviour to be enforced even in the test
  # environment, so we no longer skip the callback when Rails.env.test?
  before_action :rate_limit_user, only: [:create]
  
  # Generate authentication bridge token for authenticated user
  # GET /auth/bridge?target_url=https://custom-domain.com/path&business_id=123
  def create
    unless user_signed_in?
      render json: { error: 'Authentication required' }, status: :unauthorized
      return
    end
    
    target_url = params[:target_url]
    business_id = params[:business_id]
    
    unless valid_target_url?(target_url, business_id)
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
        Rails.logger.warn "[AuthBridge] Invalid target URL: #{target_url} - #{e.message}"
        render json: { error: 'Invalid target URL' }, status: :bad_request
        return
      end
      
        # Create database-backed auth token (short-lived, secure)
        auth_token = AuthToken.create_for_user!(
          current_user,
          target_url,
          request
        )
      
      # Build redirect URL to custom domain's token consumption endpoint
      # This avoids embedding tokens in query params for better security
      
      # Route to the token consumption endpoint on the target domain
      consumption_url = "#{uri.scheme}://#{uri.host}"
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
      # Consume the database-backed token
      auth_token = AuthToken.consume!(token, request)
      
      unless auth_token
        Rails.logger.warn "[AuthBridge] Invalid or expired token attempted from #{SecurityConfig.client_ip(request)}"
        redirect_to '/', alert: 'Invalid or expired authentication token'
        return
      end
      
      # Sign in the user on this domain
      sign_in(auth_token.user)
      
      Rails.logger.info "[AuthBridge] Successfully authenticated user #{auth_token.user.id} on custom domain #{request.host}"
      
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
  
  private
  
  def ensure_main_domain
    unless main_domain_request?
      render json: { error: 'This endpoint is only available on the main domain' }, status: :forbidden
    end
  end
  
  def build_redirect_from_target_url(target_url, original_query, additional_query = nil)
    return '/' unless target_url.present?
    
    begin
      # Parse the target URL to extract path and existing query parameters
      uri = URI.parse(target_url)
      
      # SECURITY: Use sanitize_redirect_path to validate the full target URL first
      sanitized_path = sanitize_redirect_path(target_url)
      return sanitized_path if sanitized_path == '/' # Security rejection or invalid URL
      
      # Extract path from the original target URL (after security validation)
      base_path = uri.path.present? ? uri.path : '/'
      
      # Merge all query parameters with deduplication
      merged_query = merge_query_parameters(uri.query, original_query, additional_query)
      
      # Build final path
      final_path = merged_query.present? ? "#{base_path}?#{merged_query}" : base_path
      
      Rails.logger.debug "[AuthBridge] Built redirect path: #{final_path} from target_url: #{target_url}"
      return final_path
      
    rescue URI::InvalidURIError => e
      Rails.logger.warn "[AuthBridge] Invalid target URL: #{target_url} - #{e.message}"
      return '/'
    end
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
        result = uri.path
        result += "?#{uri.query}" if uri.query.present?
        return result
      end
      
      # Ensure path starts with /
      path = uri.path
      path = "/#{path}" unless path.start_with?('/')
      
      # Remove any dangerous characters or patterns
      path = path.gsub(/[<>'"&]/, '')
      
      # Validate path doesn't contain directory traversal
      if path.include?('../') || path.include?('..\\')
        Rails.logger.warn "[AuthBridge] Rejected path traversal attempt: #{redirect_to}"
        return '/'
      end
      
      # Limit path length
      if path.length > 2000
        Rails.logger.warn "[AuthBridge] Rejected overly long path: #{path.length} chars"
        return '/'
      end
      
      path
      
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
        
        # Target URL host must match business hostname
        unless uri.host == business.hostname
          Rails.logger.warn "[AuthBridge] Target URL host #{uri.host} doesn't match business hostname #{business.hostname}"
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
    # Simple rate limiting: max 10 bridge attempts per user per hour
    # Note: Tokens are database-backed; rate limiting uses Rack::Attack with Rails.cache
    cache_key = "auth_bridge_rate_limit:#{current_user.id}"
    attempts = Rails.cache.read(cache_key) || 0
    
    limit = Rails.env.test? ? 5 : 10
    if attempts >= limit
      Rails.logger.warn "[AuthBridge] Rate limit exceeded for user #{current_user.id}"
      render json: { error: 'Rate limit exceeded' }, status: :too_many_requests
      return
    end
    
    # Increment counter with 1 hour expiry
    Rails.cache.write(cache_key, attempts + 1, expires_in: 1.hour)
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