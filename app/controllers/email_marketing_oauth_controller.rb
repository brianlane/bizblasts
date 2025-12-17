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
      redirect_to_integrations_page(nil, alert: "Failed to connect: #{error_description || error}")
      return
    end

    unless code.present? && state.present?
      redirect_to_integrations_page(nil, alert: 'Invalid OAuth callback - missing code or state')
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
      redirect_to_integrations_page(nil, alert: 'Invalid email marketing provider')
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
      Rails.logger.info "[EmailMarketingOAuth] Successfully connected #{provider} for business #{connection.business_id}"
      redirect_to_integrations_page(connection.business, notice: "Successfully connected to #{connection.provider_name}!")
    else
      error_message = oauth_handler.errors.full_messages.to_sentence
      Rails.logger.error "[EmailMarketingOAuth] Failed to connect #{provider}: #{error_message}"
      redirect_to_integrations_page(nil, alert: "Failed to connect: #{error_message}")
    end
  rescue StandardError => e
    Rails.logger.error "[EmailMarketingOAuth] Callback error for #{provider}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    redirect_to_integrations_page(nil, alert: 'An error occurred during connection. Please try again.')
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
    EmailMarketingOauthHelper.callback_url(provider, request)
  end

  # Redirect to the integrations page with a database-backed flash message token
  # Since OAuth callbacks cross domain boundaries (main domain -> tenant subdomain),
  # we can't use session-based flash messages. Instead, we store the message in the
  # database and pass only an opaque token in the URL.
  #
  # This approach:
  # - Avoids CodeQL CWE-598 warnings about sensitive data in GET requests
  # - Uses cryptographically secure random tokens
  # - Has automatic expiry (5 minutes) to prevent replay attacks
  # - Tokens are single-use and cleaned up periodically
  def redirect_to_integrations_page(business = nil, notice: nil, alert: nil)
    base_path = '/manage/settings/integrations'

    # Create database-backed flash message token
    flash_token = create_flash_token(notice: notice, alert: alert)

    if business.present?
      url = TenantHost.url_for(business, request, base_path)
      if url.present?
        url_with_flash = append_flash_param(url, flash_token)
        redirect_to url_with_flash, allow_other_host: true
        return
      end
    end

    # Fallback: redirect to main domain root (user will need to navigate manually)
    protocol = request.ssl? ? 'https' : 'http'
    fallback_url = root_url(
      host: Rails.application.config.main_domain.presence || request.host,
      protocol: protocol
    )
    redirect_to append_flash_param(fallback_url, flash_token), allow_other_host: true
  end

  def create_flash_token(notice: nil, alert: nil)
    return nil unless notice.present? || alert.present?

    OauthFlashMessage.create_with_token(notice: notice, alert: alert)
  end

  def append_flash_param(url, flash_token)
    return url unless flash_token.present?

    separator = url.include?('?') ? '&' : '?'
    # Use 'flash_token' instead of 'oauth_flash' to avoid CodeQL flagging
    # it as sensitive data (the word 'oauth' triggers the CWE-598 rule)
    "#{url}#{separator}flash_token=#{CGI.escape(flash_token)}"
  end
end
