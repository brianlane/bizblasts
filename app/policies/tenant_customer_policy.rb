# frozen_string_literal: true

class TenantCustomerPolicy < BusinessPolicy
  # Business managers and staff can list customers belonging to their business
  def index?
    return false unless user.present? && user.business_id.present? && user.has_any_role?(:manager, :staff)
    # Only allow if record is a class or belongs to the user's business
    !record.respond_to?(:business_id) || record.business_id == user.business_id
  end

  # Can view customer details
  def show?
    index?
  end

  # Can create new customers
  def create?
    index?
  end

  # Alias new to create
  def new?
    create?
  end

  # Can update existing customers
  def update?
    user.present? && user.business_id.present? && user.has_any_role?(:manager, :staff) && record.business_id == user.business_id
  end

  # Alias edit to update
  def edit?
    update?
  end

  # Can delete customers
  def destroy?
    update?
  end

  class Scope < Scope
    def resolve
      if user.present? && user.business_id.present? && user.has_any_role?(:manager, :staff)
        scope.where(business_id: user.business_id)
      else
        scope.none
      end
    end
  end
end 