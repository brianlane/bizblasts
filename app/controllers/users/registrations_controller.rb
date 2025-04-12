# frozen_string_literal: true

# Base controller for user registrations (both client and business owners)
class Users::RegistrationsController < Devise::RegistrationsController
  # before_action :configure_sign_up_params, only: [:create]
  # before_action :configure_account_update_params, only: [:update]

  # Add ability to set tenant from params (only in test mode)
  allow_tenant_params if respond_to?(:allow_tenant_params)

  # Override Devise methods here if common logic is needed for both
  # client and business registrations.

  protected

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_sign_up_params
  #   devise_parameter_sanitizer.permit(:sign_up, keys: [:attribute])
  # end

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_account_update_params
  #   devise_parameter_sanitizer.permit(:account_update, keys: [:attribute])
  # end

  # The path used after sign up for inactive accounts.
  # def after_inactive_sign_up_path_for(resource)
  #   super(resource)
  # end

  # Redirect to root path after successful sign up
  # This can be overridden in specific controllers if needed.
  def after_sign_up_path_for(resource)
    # Debugging: Check resource state
    Rails.logger.debug "[RegistrationsController] after_sign_up_path_for called."
    Rails.logger.debug "[RegistrationsController] Resource persisted?: #{resource.persisted?}"
    Rails.logger.debug "[RegistrationsController] Resource errors: #{resource.errors.full_messages.join(', ')}" if resource.errors.any?
    Rails.logger.debug "[RegistrationsController] Resource role: #{resource.role}"

    root_path
  end
end 