# frozen_string_literal: true

class CalendarOauthController < ApplicationController
  # SECURITY: CSRF skip narrowly scoped to OAuth callback only
  #
  # OAuth 2.0 security model:
  # - External providers (Google, Microsoft) initiate callbacks to this endpoint
  # - Cannot provide Rails CSRF token (external request, no session)
  # - CSRF protection provided by OAuth state parameter validation
  # - State parameter cryptographically signed via Rails.application.message_verifier
  # - State validation in handle_callback (line 43) and redirect_to_error (line 112)
  #
  # Skip justification:
  # - only: [:callback] - Narrowly scoped to single action
  # - No user state modification without valid state parameter
  # - OAuth spec requires this pattern for external provider callbacks
  #
  # Defense-in-depth:
  # - State parameter prevents CSRF (OAuth spec requirement)
  # - Message verifier ensures state authenticity
  # - All other actions use full CSRF protection
  #
  # Related: CWE-352 CSRF protection, OAuth 2.0 RFC 6749 Section 10.12
  # External OAuth providers (Google, Microsoft) cannot include Rails CSRF tokens in callbacks
  # Security provided by cryptographically signed state parameter (Rails.application.message_verifier)
  # State validation in handle_callback (line 56) and redirect_to_error (line 125)
  # codeql[rb/csrf-protection-disabled] Legitimate: OAuth callback uses state parameter for CSRF protection (OAuth 2.0 RFC 6749 Section 10.12)
  skip_before_action :verify_authenticity_token, only: [:callback]

  def callback
    provider = params[:provider]
    code = params[:code]
    state = params[:state]
    error = params[:error]
    
    # Handle OAuth errors
    if error.present?
      handle_oauth_error(error, params[:error_description])
      return
    end
    
    # Validate required parameters
    unless provider.present? && code.present? && state.present?
      redirect_to_error("Missing required OAuth parameters")
      return
    end
    
    # Process the OAuth callback
    oauth_handler = Calendar::OauthHandler.new
    scheme = request.ssl? ? 'https' : 'http'
    host = Rails.application.config.main_domain
    # Append port only if main_domain does NOT already include one
    port_str = if host.include?(':') || request.port.nil? || [80, 443].include?(request.port)
                 ''
               else
                 ":#{request.port}"
               end
    redirect_uri = "#{scheme}://#{host}#{port_str}/oauth/calendar/#{provider}/callback"
    
    calendar_connection = oauth_handler.handle_callback(provider, code, state, redirect_uri)
    
    if calendar_connection
      handle_successful_connection(calendar_connection)
    else
      handle_failed_connection(oauth_handler.errors)
    end
  end
  
  private
  
  def handle_oauth_error(error, description = nil)
    Rails.logger.error("OAuth error: #{error} - #{description}")
    
    case error
    when 'access_denied'
      redirect_to_error("Calendar access was denied. Please try again if you want to connect your calendar.")
    when 'invalid_request'
      redirect_to_error("Invalid OAuth request. Please try again.")
    when 'unauthorized_client'
      redirect_to_error("Unauthorized calendar application. Please contact support.")
    when 'unsupported_response_type'
      redirect_to_error("Unsupported OAuth response type. Please contact support.")
    when 'invalid_scope'
      redirect_to_error("Invalid calendar permissions requested. Please contact support.")
    when 'server_error'
      redirect_to_error("Calendar service is temporarily unavailable. Please try again later.")
    when 'temporarily_unavailable'
      redirect_to_error("Calendar service is temporarily unavailable. Please try again later.")
    else
      redirect_to_error("Calendar connection failed: #{description || error}")
    end
  end
  
  def handle_successful_connection(calendar_connection)
    business = calendar_connection.business
    
    # Generate success message
    provider_name = calendar_connection.provider_display_name
    staff_name = calendar_connection.staff_member.name
    
    flash[:notice] = "Successfully connected #{provider_name} for #{staff_name}! Your bookings will now sync automatically."
    
    # Redirect to business subdomain calendar settings
    redirect_to_business_calendar_settings(business)
  end
  
  def handle_failed_connection(errors)
    error_messages = errors.full_messages.join('. ')
    Rails.logger.error("Calendar connection failed: #{error_messages}")
    
    # Try to redirect to the business if we can determine it from the state
    # Otherwise redirect to main domain with error
    redirect_to_error("Failed to connect calendar: #{error_messages}")
  end
  
  # Redirect the user back to their business settings page, preserving
  # custom-domain vs subdomain hosting.
  def redirect_to_business_calendar_settings(business)
    target_url = TenantHost.url_for(business, request, '/manage/settings/integrations')
    redirect_to target_url, allow_other_host: true
  end
  
  def redirect_to_error(message)
    # Try to redirect to a business subdomain if we can determine it
    # Otherwise redirect to main domain
    
    if params[:state].present?
      begin
        state_data = Rails.application.message_verifier(:calendar_oauth).verify(params[:state])
        business = Business.find(state_data['business_id'])
        
        if business.present?
          # Redirect back to the business-appropriate host (subdomain or custom domain)
          redirect_to TenantHost.url_for(business, request, '/manage/settings/integrations'), alert: message
          return
        end
      rescue => e
        Rails.logger.warn("Could not parse OAuth state for error redirect: #{e.message}")
      end
    end
    
    # Fallback to root with error
    redirect_to root_path, alert: message
  end
end