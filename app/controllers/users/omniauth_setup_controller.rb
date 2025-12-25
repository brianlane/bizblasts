# frozen_string_literal: true

module Users
  # Handles pre-OAuth setup before redirecting to the OAuth provider
  # This controller stores necessary context (registration type, return URL, etc.)
  # in the session before initiating the OAuth flow.
  class OmniauthSetupController < ApplicationController
    # Skip tenant for OAuth setup
    skip_before_action :set_tenant, raise: false

    # CSRF protection is important here since this is a POST action
    # The form that posts here must include authenticity_token

    # POST /users/auth/google_oauth2/setup
    # Stores context in session and redirects to OAuth provider
    def setup
      # Store registration type (client, business, or nil for sign-in)
      # Validate to prevent privilege escalation - only allow 'client' and 'business'
      registration_type = params[:registration_type]
      if registration_type.present?
        # Whitelist only allowed registration types
        unless ['client', 'business'].include?(registration_type.to_s.downcase)
          Rails.logger.warn "[OmniauthSetup] Invalid registration_type attempted: #{registration_type}"
          redirect_to root_path, alert: "Invalid registration type" and return
        end
        session[:omniauth_registration_type] = registration_type.to_s.downcase
      end

      # Store return URL for after OAuth
      return_url = params[:return_url].presence || request.referer
      session[:omniauth_return_url] = return_url if return_url.present?

      # Store origin host for cross-domain support
      session[:omniauth_origin_host] = request.host

      # Store business ID if provided (for tenant context)
      if params[:business_id].present?
        session[:omniauth_business_id] = params[:business_id]
      end

      Rails.logger.info "[OmniauthSetup] Initiating OAuth: registration_type=#{registration_type}, return_url=#{return_url}, origin=#{request.host}"

      # Redirect to the actual OmniAuth path
      # OmniAuth handles the OAuth redirect to Google
      redirect_to user_google_oauth2_omniauth_authorize_path, allow_other_host: false
    end
  end
end

