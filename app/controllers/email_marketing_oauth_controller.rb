# frozen_string_literal: true

# Handles OAuth callbacks for email marketing integrations (Mailchimp, Constant Contact)
class EmailMarketingOauthController < ApplicationController
  # GET /oauth/email-marketing/:provider/callback
  def callback
    provider = params[:provider]
    code = params[:code]
    state = params[:state]
    error = params[:error]
    error_description = params[:error_description]

    # Handle OAuth errors
    if error.present?
      Rails.logger.error "[EmailMarketingOAuth] OAuth error for #{provider}: #{error} - #{error_description}"
      session[:oauth_flash_alert] = "Failed to connect: #{error_description || error}"
      redirect_to_integrations_page
      return
    end

    unless code.present? && state.present?
      session[:oauth_flash_alert] = 'Invalid OAuth callback - missing code or state'
      redirect_to_integrations_page
      return
    end

    # NOTE: We do NOT use session-based state validation here because OAuth flow
    # crosses domain boundaries (tenant subdomain/custom domain -> main domain callback).
    # Session cookies are scoped by domain, so the main domain won't have access to
    # the session from the tenant domain.
    #
    # Instead, CSRF protection is provided by the cryptographically-signed state parameter:
    # - State is generated using Rails.application.message_verifier(:email_marketing_oauth)
    # - Contains business_id, provider, timestamp, and nonce
    # - Verified in oauth_handler.handle_callback via verify_state method
    # - Has 15-minute expiry to prevent replay attacks
    # - Invalid/tampered states are rejected by the message verifier

    oauth_handler = build_oauth_handler(provider)
    unless oauth_handler
      session[:oauth_flash_alert] = 'Invalid email marketing provider'
      redirect_to_integrations_page
      return
    end

    # Build redirect URI (must match what was used in authorization)
    redirect_uri = email_marketing_oauth_callback_url(provider)

    connection = oauth_handler.handle_callback(
      code: code,
      state: state,
      redirect_uri: redirect_uri
    )

    if connection
      session[:oauth_flash_notice] = "Successfully connected to #{connection.provider_name}!"
      Rails.logger.info "[EmailMarketingOAuth] Successfully connected #{provider} for business #{connection.business_id}"
    else
      error_message = oauth_handler.errors.full_messages.to_sentence
      session[:oauth_flash_alert] = "Failed to connect: #{error_message}"
      Rails.logger.error "[EmailMarketingOAuth] Failed to connect #{provider}: #{error_message}"
    end

    redirect_to_integrations_page
  rescue StandardError => e
    Rails.logger.error "[EmailMarketingOAuth] Callback error for #{provider}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    session[:oauth_flash_alert] = 'An error occurred during connection. Please try again.'
    redirect_to_integrations_page
  end

  private

  def build_oauth_handler(provider)
    case provider.to_s
    when 'mailchimp'
      EmailMarketing::Mailchimp::OauthHandler.new
    when 'constant-contact', 'constant_contact'
      EmailMarketing::ConstantContact::OauthHandler.new
    else
      nil
    end
  end

  def email_marketing_oauth_callback_url(provider)
    scheme = request.ssl? ? 'https' : 'http'
    host = Rails.application.config.main_domain.presence || request.host
    port_str = if host&.include?(':') || request.port.nil? || [80, 443].include?(request.port)
                 ''
               else
                 ":#{request.port}"
               end
    "#{scheme}://#{host}#{port_str}/oauth/email-marketing/#{provider}/callback"
  end

  def redirect_to_integrations_page
    # The state should contain the business_id, but we redirect to main domain
    # which will then route appropriately
    redirect_to business_manager_settings_integrations_url(
      host: Rails.application.config.main_domain.presence || request.host,
      protocol: request.ssl? ? 'https' : 'http'
    )
  end
end
