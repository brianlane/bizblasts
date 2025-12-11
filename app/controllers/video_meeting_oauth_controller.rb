# frozen_string_literal: true

class VideoMeetingOauthController < ApplicationController
  # SECURITY: Proper CSRF protection for OAuth callbacks
  #
  # OAuth 2.0 security model:
  # - External providers (Zoom, Google) initiate callbacks to this endpoint
  # - Cannot provide Rails CSRF token (external request, no prior session)
  # - CSRF protection provided by OAuth state parameter validation (OAuth 2.0 RFC 6749 Section 10.12)
  # - State parameter cryptographically signed via Rails.application.message_verifier
  # - State includes timestamp validation (15-minute expiration) and nonce (prevents replay)
  #
  # Implementation:
  # - Rails CSRF protection enabled (protect_from_forgery with: :exception)
  # - before_action validates OAuth state parameter before processing
  # - verified_request? override recognizes valid OAuth state as alternative CSRF protection
  # - Defense-in-depth: Both OAuth state AND Rails CSRF checks active
  #
  # Standards compliance:
  # - OAuth 2.0 RFC 6749 Section 10.12: State parameter for CSRF protection
  # - OWASP CSRF Prevention: Alternative tokens for external callbacks
  # - Rails Security Guide: Custom verification for special cases
  #
  # Related: CWE-352 CSRF protection, OAuth 2.0 RFC 6749 Section 10.12

  # Keep Rails CSRF protection enabled (explicit for clarity)
  protect_from_forgery with: :exception

  # Validate OAuth state parameter before processing callback
  # This provides CSRF protection per OAuth 2.0 specification
  before_action :validate_oauth_state, only: :callback

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
    # State validation already done in before_action
    oauth_handler = VideoMeeting::OauthHandler.new
    redirect_uri = build_redirect_uri(provider)

    video_connection = oauth_handler.handle_callback(provider, code, state, redirect_uri)

    if video_connection
      handle_successful_connection(video_connection)
    else
      handle_failed_connection(oauth_handler.errors)
    end
  end

  private

  def build_redirect_uri(provider)
    scheme = request.ssl? ? 'https' : 'http'
    host = Rails.application.config.main_domain
    # Append port only if main_domain does NOT already include one
    port_str = if host.include?(':') || request.port.nil? || [80, 443].include?(request.port)
                 ''
               else
                 ":#{request.port}"
               end

    # Map provider to URL path
    provider_path = case provider.to_s
                    when 'zoom' then 'zoom'
                    when 'google_meet' then 'google-meet'
                    else provider
                    end

    "#{scheme}://#{host}#{port_str}/oauth/video/#{provider_path}/callback"
  end

  # Validate OAuth state parameter for CSRF protection
  # Per OAuth 2.0 RFC 6749 Section 10.12, the state parameter serves as CSRF token
  def validate_oauth_state
    unless params[:state].present? && valid_oauth_state?(params[:state])
      Rails.logger.warn("[VideoMeetingOauth] Invalid or expired OAuth state parameter")
      redirect_to root_path, alert: "Invalid or expired video meeting connection request. Please try again." and return
    end
  end

  # Verify OAuth state parameter
  # Checks:
  # - Cryptographic signature (Rails.application.message_verifier)
  # - Timestamp (must be within 15 minutes)
  # - Returns true only if both checks pass
  def valid_oauth_state?(state)
    return false if state.blank?

    begin
      state_data = Rails.application.message_verifier(:video_meeting_oauth).verify(state)

      # Check if state is not too old (15 minutes max)
      timestamp_valid = (Time.current.to_i - state_data['timestamp']) <= 15.minutes

      return timestamp_valid
    rescue ActiveSupport::MessageVerifier::InvalidSignature => e
      Rails.logger.warn("[VideoMeetingOauth] Invalid OAuth state signature: #{e.message}")
      return false
    rescue => e
      Rails.logger.error("[VideoMeetingOauth] Error validating OAuth state: #{e.message}")
      return false
    end
  end

  # Override Rails' verified_request? to recognize valid OAuth state as CSRF protection
  # This implements alternative CSRF protection per Rails security best practices
  # The OAuth state parameter serves the same purpose as a CSRF token:
  # - Cryptographically signed
  # - Time-limited
  # - Verified before processing
  def verified_request?
    # First try Rails' standard CSRF token verification
    super || valid_oauth_callback_request?
  end

  # Check if this is a valid OAuth callback request with proper state validation
  def valid_oauth_callback_request?
    action_name == 'callback' &&
    params[:state].present? &&
    valid_oauth_state?(params[:state])
  end

  def handle_oauth_error(error, description = nil)
    Rails.logger.error("Video Meeting OAuth error: #{error} - #{description}")

    case error
    when 'access_denied'
      redirect_to_error("Video meeting access was denied. Please try again if you want to connect your account.")
    when 'invalid_request'
      redirect_to_error("Invalid OAuth request. Please try again.")
    when 'unauthorized_client'
      redirect_to_error("Unauthorized video meeting application. Please contact support.")
    when 'unsupported_response_type'
      redirect_to_error("Unsupported OAuth response type. Please contact support.")
    when 'invalid_scope'
      redirect_to_error("Invalid video meeting permissions requested. Please contact support.")
    when 'server_error'
      redirect_to_error("Video meeting service is temporarily unavailable. Please try again later.")
    when 'temporarily_unavailable'
      redirect_to_error("Video meeting service is temporarily unavailable. Please try again later.")
    else
      redirect_to_error("Video meeting connection failed: #{description || error}")
    end
  end

  def handle_successful_connection(video_connection)
    business = video_connection.business

    # Generate success message
    provider_name = video_connection.provider_name
    staff_name = video_connection.staff_member.name

    flash[:notice] = "Successfully connected #{provider_name} for #{staff_name}! Video meetings will now be created automatically for virtual services."

    # Redirect to business subdomain integrations settings
    redirect_to_business_integrations(business)
  end

  def handle_failed_connection(errors)
    error_messages = errors.full_messages.join('. ')
    Rails.logger.error("Video meeting connection failed: #{error_messages}")

    # Try to redirect to the business if we can determine it from the state
    # Otherwise redirect to main domain with error
    redirect_to_error("Failed to connect video meeting account: #{error_messages}")
  end

  # Redirect the user back to their business settings page, preserving
  # custom-domain vs subdomain hosting.
  def redirect_to_business_integrations(business)
    target_url = TenantHost.url_for(business, request, '/manage/settings/integrations')
    redirect_to target_url, allow_other_host: true
  end

  def redirect_to_error(message)
    # Try to redirect to the business if we can determine it from the state
    # Otherwise redirect to main domain

    if params[:state].present?
      begin
        state_data = Rails.application.message_verifier(:video_meeting_oauth).verify(params[:state])
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
