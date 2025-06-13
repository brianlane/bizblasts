# frozen_string_literal: true

# Handles client user sign-ups.
class Client::RegistrationsController < Users::RegistrationsController
  before_action :configure_sign_up_params, only: [:create]

  def create
    super do |resource|
      if resource.persisted?
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
      :first_name, :last_name, :referral_code,
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
      Rails.logger.info "[REFERRAL] Processed referral signup: #{user.email} via #{referral_code}"
    else
      Rails.logger.warn "[REFERRAL] Failed to process referral signup: #{user.email} via #{referral_code} - #{result[:error]}"
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
        Rails.logger.info "[REGISTRATION] Recorded policy acceptance: #{user.email} - #{policy_type} v#{current_version.version}"
      rescue => e
        Rails.logger.error "[REGISTRATION] Failed to record policy acceptance for #{policy_type}: #{e.message}"
      end
    end
  end
end 