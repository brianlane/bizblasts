# frozen_string_literal: true

# Defines authorization rules for Business resources.
class BusinessPolicy < ApplicationPolicy
  # Users can access the business manager if they belong to the business
  # and have the manager or staff role.
  def access_business_manager?
    # record is the @current_business passed to authorize
    # user is the current_user from Pundit
    user.present? && record.present? && user.business_id == record.id && user.has_any_role?(:manager, :staff)
  end

  # Add other policy methods as needed, e.g.:
  # def show?
  #   user.present? && (user.admin? || user.business_id == record.id)
  # end

  # def update?
  #   user.present? && user.admin? || (user.business_id == record.id && user.manager?)
  # end

  # Scope class for index actions, if needed
  class Scope < Scope
    def resolve
      if user.admin?
        scope.all
      elsif user.present?
        scope.where(id: user.business_id)
      else
        scope.none
      end
    end
  end
end 