# frozen_string_literal: true

# Handles client user sign-ups.
class Client::RegistrationsController < Users::RegistrationsController
  before_action :configure_sign_up_params, only: [:create]

  # GET /resource/sign_up
  # Overrides Devise default to prefill OAuth data before rendering the form
  def new
    build_resource({}) # Builds the User resource

    # Pre-fill from OAuth data if present (user came from Google OAuth)
    # Only use OAuth data if it was recently set (within last 10 minutes)
    if session[:omniauth_data].present? && session[:omniauth_data_timestamp].present?
      # Check if OAuth data is fresh (less than 10 minutes old)
      begin
        timestamp = Time.iso8601(session[:omniauth_data_timestamp])
        if Time.current - timestamp < 10.minutes
          oauth_data = session[:omniauth_data]
          resource.email = oauth_data[:email]
          resource.first_name = oauth_data[:first_name]
          resource.last_name = oauth_data[:last_name]
          resource.provider = oauth_data[:provider]
          resource.uid = oauth_data[:uid]
        else
          # Clear stale OAuth data
          session.delete(:omniauth_data)
          session.delete(:omniauth_data_timestamp)
        end
      rescue ArgumentError => e
        # Timestamp is malformed or corrupted - clear OAuth data
        Rails.logger.warn "[REGISTRATION] Malformed OAuth timestamp: #{e.message}"
        session.delete(:omniauth_data)
        session.delete(:omniauth_data_timestamp)
      end
    end

    respond_with resource
  end

  def create
    # Ensure params[:user] exists early to prevent NoMethodError
    # This will raise ActionController::ParameterMissing if :user is missing
    params.require(:user)

    # Handle OAuth user - merge provider/uid from session if present
    # Only use OAuth data if it was recently set (within last 10 minutes)
    oauth_data = session[:omniauth_data]
    if oauth_data.present? && session[:omniauth_data_timestamp].present?
      # Check if OAuth data is fresh (less than 10 minutes old)
      begin
        timestamp = Time.iso8601(session[:omniauth_data_timestamp])
        if Time.current - timestamp < 10.minutes
          # Merge OAuth provider and uid from session
          params[:user][:provider] = oauth_data[:provider]
          params[:user][:uid] = oauth_data[:uid]

          # OAuth users don't need to provide password in form - generate one
          unless params[:user][:password].present?
            random_password = Devise.friendly_token[0, 20]
            params[:user][:password] = random_password
            params[:user][:password_confirmation] = random_password
          end
        else
          # Clear stale OAuth data
          session.delete(:omniauth_data)
          session.delete(:omniauth_data_timestamp)

          # If form was submitted without password (OAuth flow), redirect back with error
          if params[:user][:password].blank?
            Rails.logger.info "[REGISTRATION] OAuth session expired - redirecting to re-fill form with password"
            flash[:alert] = "Your session expired. Please complete the registration form again."
            redirect_to new_client_registration_path and return
          end
        end
      rescue ArgumentError => e
        # Timestamp is malformed or corrupted - clear OAuth data
        Rails.logger.warn "[REGISTRATION] Malformed OAuth timestamp: #{e.message}"
        session.delete(:omniauth_data)
        session.delete(:omniauth_data_timestamp)

        # If form was submitted without password (OAuth flow), redirect back with error
        if params[:user][:password].blank?
          Rails.logger.info "[REGISTRATION] OAuth session corrupted - redirecting to re-fill form with password"
          flash[:alert] = "There was an issue with your session. Please complete the registration form again."
          redirect_to new_client_registration_path and return
        end
      end
    end

    super do |resource|
      if resource.persisted?
        # Clear OAuth session data if present
        session.delete(:omniauth_data)
        session.delete(:omniauth_data_timestamp)

        # Process referral code if provided
        if params[:user][:referral_code].present?
          process_referral_signup(resource, params[:user][:referral_code])
        end

        # Record policy acceptances after successful creation
        record_policy_acceptances(resource, params[:policy_acceptances]) if params[:policy_acceptances]
      end
    end
  end

  protected

  # Permit additional parameters for client sign-up.
  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [
      :first_name, :last_name, :referral_code, :phone, :bizblasts_notification_consent,
      :provider, :uid, # OAuth parameters
      policy_acceptances: {}
    ])
    # Role is automatically set to client by default in the model
  end

  # Override the build_resource method to ensure the role is explicitly client
  # This prevents someone from trying to inject a different role via params
  def build_resource(hash = {})
    super(hash)
    self.resource.role = :client
  end

  # Optional: Override path after sign up if needed
  # def after_sign_up_path_for(resource)
  #   # e.g., client_dashboard_path
  #   super(resource)
  # end

  private

  # Process referral code during signup
  def process_referral_signup(user, referral_code)
    # Store referral source on user
    user.update!(referral_source_code: referral_code)
    
    # Find the referral and business from the code
    referral = Referral.find_by(referral_code: referral_code)
    return unless referral
    
    business = referral.business
    return unless business&.referral_program_active?
    
    # Process the referral signup
    result = ReferralService.process_referral_signup(referral_code, user, business)
    
    if result[:success]
      SecureLogger.info "[REFERRAL] Processed referral signup: #{user.email} via #{referral_code}"
    else
      SecureLogger.warn "[REFERRAL] Failed to process referral signup: #{user.email} via #{referral_code} - #{result[:error]}"
    end
  rescue => e
    Rails.logger.error "[REFERRAL] Error processing referral signup: #{e.message}"
  end

  # Record policy acceptances for the user
  def record_policy_acceptances(user, policy_params)
    return unless policy_params.present?
    
    policy_params.each do |policy_type, accepted|
      next unless accepted == '1'
      
      current_version = PolicyVersion.current_version(policy_type)
      next unless current_version
      
      begin
        PolicyAcceptance.record_acceptance(user, policy_type, current_version.version, request)
        SecureLogger.info "[REGISTRATION] Recorded policy acceptance: #{user.email} - #{policy_type} v#{current_version.version}"
      rescue => e
        Rails.logger.error "[REGISTRATION] Failed to record policy acceptance for #{policy_type}: #{e.message}"
      end
    end
  end
end 