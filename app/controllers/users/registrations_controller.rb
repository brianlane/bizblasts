# frozen_string_literal: true

module Users
  # Custom registrations controller to handle tenant in tests
  class RegistrationsController < Devise::RegistrationsController
    # Add ability to set tenant from params (only in test mode)
    allow_tenant_params if respond_to?(:allow_tenant_params)
    
    private

    # Override Devise's resource_params method to add the business_id
    def sign_up_params
      devise_params = super
      
      # Setting business_id to current tenant if set
      if ActsAsTenant.current_tenant
        # Convert ActionController::Parameters to hash and merge business_id
        new_params = devise_params.to_h
        new_params[:business_id] = ActsAsTenant.current_tenant.id
        ActionController::Parameters.new(user: new_params).require(:user).permit(:email, :password, :password_confirmation, :business_id)
      else
        devise_params
      end
    end
  end
end 