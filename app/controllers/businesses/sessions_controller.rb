# frozen_string_literal: true

module Businesses
  # Custom sessions controller for businesses
  class SessionsController < Devise::SessionsController
    # Skip tenant setting for sign out
    skip_before_action :set_tenant, only: :destroy

    # You might need to customize create or after_sign_in_path_for
    # depending on business login requirements and redirection

    # Example: Override the path businesses are redirected to after sign in
    # def after_sign_in_path_for(resource)
    #   # Redirect to a business-specific dashboard or path
    #   business_dashboard_path # Assuming such a path exists
    # end

    # Example: Custom destroy action if needed
    def destroy
      super do
        # After sign out, redirect to the home page (or business login page)
        redirect_to root_path and return
      end
    end
  end
end 