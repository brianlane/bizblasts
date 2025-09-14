class AuthenticationBridgeController < ApplicationController
  # Skip tenant requirement for this controller since we're bridging across domains
  skip_before_action :set_tenant
  skip_before_action :authenticate_user!, only: [:consume]
  
  # Security: Only allow on main domain to prevent abuse
  before_action :ensure_main_domain
  before_action :rate_limit_user, only: [:create]
  
  # Generate authentication bridge token for authenticated user
  # GET /auth/bridge?target_url=https://custom-domain.com/path
  def create
    unless user_signed_in?
      render json: { error: 'Authentication required' }, status: :unauthorized
      return
    end
    
    target_url = params[:target_url]
    
    unless valid_target_url?(target_url)
      render json: { error: 'Invalid target URL' }, status: :bad_request
      return
    end
    
    begin
      bridge = AuthenticationBridge.create_for_user!(
        current_user,
        target_url,
        request.remote_ip,
        request.user_agent
      )
      
      # Add token to the target URL and redirect
      separator = target_url.include?('?') ? '&' : '?'
      redirect_url = "#{target_url}#{separator}auth_token=#{bridge.token}"
      
      Rails.logger.info "[AuthBridge] Created token for user #{current_user.id}, redirecting to #{URI(target_url).host}"
      
      redirect_to redirect_url, allow_other_host: true
      
    rescue => e
      Rails.logger.error "[AuthBridge] Failed to create bridge: #{e.message}"
      render json: { error: 'Failed to create authentication bridge' }, status: :internal_server_error
    end
  end
  
  # Consume authentication bridge token and sign in user
  # This endpoint should be called by custom domains when they receive an auth_token
  # POST /auth/bridge/consume
  def consume
    token = params[:token]
    
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
  
  def valid_target_url?(url)
    return false unless url.present?
    
    begin
      uri = URI.parse(url)
      
      # Must be HTTPS in production
      if Rails.env.production? && uri.scheme != 'https'
        return false
      end
      
      # Must have a valid host
      return false unless uri.host.present?
      
      # Don't allow redirecting to the main domain (infinite loop prevention)
      main_domains = ['bizblasts.com', 'www.bizblasts.com']
      if Rails.env.production? && main_domains.include?(uri.host)
        return false
      end
      
      # In development, allow localhost and lvh.me
      if Rails.env.development?
        allowed_patterns = [
          /localhost/,
          /127\.0\.0\.1/,
          /\.lvh\.me$/,
          /lvh\.me$/
        ]
        return true if allowed_patterns.any? { |pattern| uri.host =~ pattern }
      end
      
      # Must be a custom domain we recognize (security measure)
      custom_domain_business = Business.find_by(
        hostname: uri.host,
        host_type: 'custom_domain',
        status: 'cname_active'
      )
      
      custom_domain_business.present?
      
    rescue URI::InvalidURIError
      false
    end
  end
  
  def rate_limit_user
    # Simple rate limiting: max 10 bridge attempts per user per hour
    recent_bridges = AuthenticationBridge
      .for_user(current_user)
      .where('created_at > ?', 1.hour.ago)
      .count
      
    if recent_bridges >= 10
      render json: { error: 'Rate limit exceeded' }, status: :too_many_requests
    end
  end
  
  def main_domain_request?
    return true if Rails.env.development? || Rails.env.test?
    
    host = request.host.to_s.downcase
    host.ends_with?('bizblasts.com') || host == 'bizblasts.com'
  end
end