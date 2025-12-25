# frozen_string_literal: true

# Shared OAuth registration functionality for client and business registration controllers
# Handles OAuth data prefill and session management during registration
module OauthRegistration
  extend ActiveSupport::Concern

  # OAuth session timeout - data older than this is considered stale
  OAUTH_SESSION_TIMEOUT = 10.minutes

  private

  # Prefill resource from OAuth session data if present and valid
  # @param resource [User] The user resource to prefill
  def prefill_from_oauth_data(resource)
    return unless session[:omniauth_data].present? && session[:omniauth_data_timestamp].present?

    begin
      timestamp = Time.iso8601(session[:omniauth_data_timestamp])
      if Time.current - timestamp < OAUTH_SESSION_TIMEOUT
        # OAuth data is fresh - prefill the form
        oauth_data = session[:omniauth_data]
        resource.email = oauth_data[:email]
        resource.first_name = oauth_data[:first_name]
        resource.last_name = oauth_data[:last_name]
        resource.provider = oauth_data[:provider]
        resource.uid = oauth_data[:uid]
      else
        # OAuth data is stale - clear it
        clear_oauth_session_data
      end
    rescue ArgumentError => e
      # Timestamp is malformed or corrupted - clear OAuth data
      Rails.logger.warn "[REGISTRATION] Malformed OAuth timestamp: #{e.message}"
      clear_oauth_session_data
    end
  end

  # Process OAuth data during form submission
  # Merges provider/uid and generates password if needed
  # @param params_hash [Hash] The params hash to merge OAuth data into (for client controller)
  # @param user_params [ActionController::Parameters] The user params to merge OAuth data into (for business controller)
  # @param registration_path [Symbol] The registration path to redirect to on session expiry
  # @return [ActionController::Parameters, Hash, nil] The merged params, or nil if redirected
  def process_oauth_data_for_submission(params_hash: nil, user_params: nil, registration_path:)
    oauth_data = session[:omniauth_data]
    return params_hash || user_params unless oauth_data.present? && session[:omniauth_data_timestamp].present?

    begin
      timestamp = Time.iso8601(session[:omniauth_data_timestamp])
      if Time.current - timestamp < OAUTH_SESSION_TIMEOUT
        # OAuth data is fresh - use it
        if params_hash
          # Client controller style (direct params modification)
          params_hash[:provider] = oauth_data[:provider]
          params_hash[:uid] = oauth_data[:uid]

          # Generate password if not provided
          unless params_hash[:password].present?
            random_password = Devise.friendly_token[0, 20]
            params_hash[:password] = random_password
            params_hash[:password_confirmation] = random_password
          end
          return params_hash
        elsif user_params
          # Business controller style (params merging)
          merged_params = user_params.merge(
            provider: oauth_data[:provider],
            uid: oauth_data[:uid]
          )

          # Generate password if not provided
          unless merged_params[:password].present?
            random_password = Devise.friendly_token[0, 20]
            merged_params = merged_params.merge(
              password: random_password,
              password_confirmation: random_password
            )
          end
          return merged_params
        end
      else
        # OAuth data expired
        handle_expired_oauth_session(params_hash, user_params, registration_path)
      end
    rescue ArgumentError => e
      # Timestamp is malformed
      handle_corrupted_oauth_session(params_hash, user_params, registration_path, e)
    end
  end

  # Handle expired OAuth session
  def handle_expired_oauth_session(params_hash, user_params, registration_path)
    clear_oauth_session_data

    # Check if form was submitted without password (OAuth flow)
    password_blank = if params_hash
                       params_hash[:password].blank?
                     elsif user_params
                       user_params[:password].blank?
                     else
                       false
                     end

    if password_blank
      Rails.logger.info "[REGISTRATION] OAuth session expired - redirecting to re-fill form with password"
      flash[:alert] = "Your session expired. Please complete the registration form again."
      redirect_to registration_path and return
    end

    # Return params so registration can proceed normally
    params_hash || user_params
  end

  # Handle corrupted OAuth session
  def handle_corrupted_oauth_session(params_hash, user_params, registration_path, error)
    Rails.logger.warn "[REGISTRATION] Malformed OAuth timestamp: #{error.message}"
    clear_oauth_session_data

    # Check if form was submitted without password (OAuth flow)
    password_blank = if params_hash
                       params_hash[:password].blank?
                     elsif user_params
                       user_params[:password].blank?
                     else
                       false
                     end

    if password_blank
      Rails.logger.info "[REGISTRATION] OAuth session corrupted - redirecting to re-fill form with password"
      flash[:alert] = "There was an issue with your session. Please complete the registration form again."
      redirect_to registration_path and return
    end

    # Return params so registration can proceed normally
    params_hash || user_params
  end

  # Clear OAuth session data
  def clear_oauth_session_data
    session.delete(:omniauth_data)
    session.delete(:omniauth_data_timestamp)
  end
end
