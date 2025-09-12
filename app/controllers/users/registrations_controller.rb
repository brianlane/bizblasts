# frozen_string_literal: true

# Base controller for user registrations (both client and business owners)
class Users::RegistrationsController < Devise::RegistrationsController
  # Ensure that all sign-up pages are served from the platform’s base domain
  # to avoid cross-domain authentication issues.
  before_action :redirect_registration_from_subdomain, only: [:new, :create]
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

  private

  # Redirect registration attempts made on a tenant (subdomain/custom) host back
  # to the main application domain, preserving the requested path.
  def redirect_registration_from_subdomain
    return if TenantHost.main_domain?(request.host)

    target_url = TenantHost.main_domain_url_for(request, request.fullpath)
    Rails.logger.info "[Redirect Registration] Sign-up attempted from tenant host; redirecting to #{target_url}"
    redirect_to target_url, status: :moved_permanently, allow_other_host: true and return
  end
end 