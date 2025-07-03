class EstimatePolicy < ApplicationPolicy
  # Scope: Business managers see all; tenant customers can see their own by token
  class Scope < Scope
    def resolve
      if user&.manager? || user&.staff?
        scope.where(business: user.business)
      elsif user&.client?
        scope.joins(:tenant_customer).where(tenant_customers: { user_id: user.id })
      else
        scope.none
      end
    end
  end

  def index?
    user&.manager? || user&.staff?
  end

  def show?
    return true if (user&.manager? || user&.staff?) && user.business == record.business
    # Allow client access if they are the tenant customer
    record.tenant_customer&.user == user
  end

  def create?
    (user&.manager? || user&.staff?) && record.business == user.business
  end

  def update?
    (user&.manager? || user&.staff?) && user.business == record.business
  end

  def destroy?
    (user&.manager? || user&.staff?) && user.business == record.business
  end

  def send_to_customer?
    (user&.manager? || user&.staff?) && user.business == record.business
  end

  def approve?
    true # Public approval via token
  end

  def decline?
    true # Public decline via token
  end

  def request_changes?
    true # Public request changes via token
  end
end 