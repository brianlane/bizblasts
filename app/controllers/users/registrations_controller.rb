# frozen_string_literal: true

module Users
  # Custom registrations controller to handle tenant in tests
  class RegistrationsController < Devise::RegistrationsController
    # Add ability to set tenant from params (only in test mode)
    allow_tenant_params if respond_to?(:allow_tenant_params)
    
    private

    # Override Devise's resource_params method to add the business_id
    def sign_up_params
      devise_params = super # This already returns permitted params
      
      # Merge business_id if current_tenant is set
      if ActsAsTenant.current_tenant
        devise_params.merge(business_id: ActsAsTenant.current_tenant.id)
      else
        devise_params
      end
    end

    # Redirect to root path after successful sign up
    def after_sign_up_path_for(resource)
      # Debugging: Check resource state
      Rails.logger.debug "[RegistrationsController] after_sign_up_path_for called."
      Rails.logger.debug "[RegistrationsController] Resource persisted?: #{resource.persisted?}"
      Rails.logger.debug "[RegistrationsController] Resource errors: #{resource.errors.full_messages.join(', ')}" if resource.errors.any?
      Rails.logger.debug "[RegistrationsController] Resource business_id: #{resource.business_id}"
      
      root_path
    end
  end
end 