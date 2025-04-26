# frozen_string_literal: true

# Default policy used by Pundit via ActiveAdmin configuration
# when a specific policy cannot be found for a resource or page.
# Inherits the default admin access rules from ApplicationPolicy.
module Admin
  class DefaultPolicy < ApplicationPolicy
    # The Scope is inherited from ApplicationPolicy, which allows all for admins.
    # Action methods (index?, show?, etc.) are inherited from ApplicationPolicy,
    # which allow actions if the user is an AdminUser.
    
    # Add overrides here if a different default behavior is needed.
    
    # Allow admin users to access custom actions
    def method_missing(method_name, *args, &block)
      # Allow all member actions if the method ends with a question mark
      # and the user is an admin
      return admin? if method_name.to_s.end_with?('?')
      super
    end
    
    def respond_to_missing?(method_name, include_private = false)
      method_name.to_s.end_with?('?') || super
    end
  end
end 