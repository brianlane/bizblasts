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
  end
end 