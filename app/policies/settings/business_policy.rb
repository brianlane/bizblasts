# frozen_string_literal: true

class Settings::BusinessPolicy < ApplicationPolicy
  # record is @business (the current tenant)
  # user is current_user (from Devise)

  # Used for both edit and update actions in Settings::BusinessController
  def update_settings?
    # User must be present, business record must be present,
    # and the user must belong to this business.
    # This assumes a User model has a `business` association (e.g., user.business_id == record.id)
    # or a more complex role/permission check (e.g. user.is_manager_for?(record)).
    # For now, a simple check that the user is associated with this specific business record.
    user.present? && record.present? && user.business == record
  end

  # Scope class might be needed if you list businesses, but for settings of the current business,
  # the authorization is typically done on the instance.
  # class Scope < Scope
  #   def resolve
  #     scope.where(id: user.business_id) # Example: user can only see their own business settings
  #   end
  # end
end 