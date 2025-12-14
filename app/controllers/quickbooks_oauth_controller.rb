# frozen_string_literal: true

class QuickbooksOauthController < ApplicationController
  protect_from_forgery with: :exception

  before_action :validate_oauth_state, only: :callback

  # GET /oauth/quickbooks/callback
  def callback
    code = params[:code]
    state = params[:state]
    realm_id = params[:realmId]
    error = params[:error]

    if error.present?
      handle_oauth_error(error, params[:error_description])
      return
    end

    unless code.present? && state.present?
      redirect_to_error('Missing required OAuth parameters')
      return
    end

    scheme = request.ssl? ? 'https' : 'http'
    host = Rails.application.config.main_domain.presence || request.host
    port_str = if host&.include?(':') || request.port.nil? || [80, 443].include?(request.port)
                 ''
               else
                 ":#{request.port}"
               end
    redirect_uri = "#{scheme}://#{host}#{port_str}/oauth/quickbooks/callback"

    oauth_handler = Quickbooks::OauthHandler.new
    connection = oauth_handler.handle_callback(code: code, state: state, realm_id: realm_id, redirect_uri: redirect_uri)

    if connection
      session[:oauth_flash_notice] = 'QuickBooks connected successfully!'
      session.delete(:oauth_flash_alert)
      redirect_to TenantHost.url_for(connection.business, request, '/manage/settings/integrations'), allow_other_host: true
    else
      session[:oauth_flash_alert] = oauth_handler.errors.full_messages.to_sentence.presence || 'Failed to connect QuickBooks.'
      session.delete(:oauth_flash_notice)
      redirect_to_error(session[:oauth_flash_alert])
    end
  end

  private

  def validate_oauth_state
    return if params[:state].present? && valid_oauth_state?(params[:state])

    Rails.logger.warn('[QuickbooksOauth] Invalid or expired OAuth state parameter')
    redirect_to root_path, alert: 'Invalid or expired QuickBooks connection request. Please try again.'
  end

  def valid_oauth_state?(state)
    return false if state.blank?

    begin
      state_data = Rails.application.message_verifier(:quickbooks_oauth).verify(state)
      timestamp = state_data['timestamp']
      return false unless timestamp.present?

      (Time.current.to_i - timestamp.to_i) <= 15.minutes.to_i
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      false
    rescue => e
      Rails.logger.error("[QuickbooksOauth] Error validating OAuth state: #{e.message}")
      false
    end
  end

  # Allow OAuth state to serve as CSRF protection for this callback.
  def verified_request?
    super || (action_name == 'callback' && params[:state].present? && valid_oauth_state?(params[:state]))
  end

  def handle_oauth_error(error, description = nil)
    Rails.logger.error("[QuickbooksOauth] OAuth error: #{error} - #{description}")

    message = case error
              when 'access_denied'
                'QuickBooks access was denied. Please try again if you want to connect QuickBooks.'
              else
                "QuickBooks connection failed: #{description || error}"
              end

    redirect_to_error(message)
  end

  def redirect_to_error(message)
    # Try to redirect to the business if we can determine it from state
    if params[:state].present?
      begin
        state_data = Rails.application.message_verifier(:quickbooks_oauth).verify(params[:state])
        business = Business.find_by(id: state_data['business_id'])
        if business
          session[:oauth_flash_alert] = message
          session.delete(:oauth_flash_notice)
          redirect_to TenantHost.url_for(business, request, '/manage/settings/integrations'), alert: message, allow_other_host: true
          return
        end
      rescue => e
        Rails.logger.warn("[QuickbooksOauth] Could not parse OAuth state for error redirect: #{e.message}")
      end
    end

    redirect_to root_path, alert: message
  end
end
