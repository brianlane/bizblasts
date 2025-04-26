# frozen_string_literal: true

# Defines authorization rules for StaffMember resources.
# Inherits defaults from BusinessPolicy, but overrides actions based on user role within their business.
class StaffMemberPolicy < BusinessPolicy
  # Can the user see the list of staff members for their business? (Managers & Staff)
  def index?
    # User must belong to a business and be manager or staff
    user.present? && user.business_id.present? && user.has_any_role?(:manager, :staff)
  end

  # Can the user view the form to create a new staff member? (Managers only)
  def new?
    create?
  end

  # Can the user create a new staff member for their business? (Managers only)
  def create?
    user.present? && user.business_id.present? && user.manager?
  end

  # Can the user view the form to edit an existing staff member? (Managers only)
  def edit?
    update?
  end

  # Can the user update an existing staff member belonging to their business? (Managers only)
  def update?
    # User must be manager, and staff member must belong to the user's business
    user.present? && user.manager? && record.present? && record.business_id == user.business_id
  end

  # Can the user delete an existing staff member belonging to their business? (Managers only)
  def destroy?
    # User must be manager, and staff member must belong to the user's business
    user.present? && user.manager? && record.present? && record.business_id == user.business_id
  end

  # Can the user manage availability of a staff member?
  def manage_availability?
    # User must be manager, and staff member must belong to the user's business
    user.present? && user.manager? && record.present? && record.business_id == user.business_id
  end

  # Scope class to filter staff members based on user role and business tenancy.
  class Scope < Scope
    def resolve
      if user.present? && user.business_id.present? && user.has_any_role?(:manager, :staff)
        # Scope staff members to the user's current business
        scope.where(business_id: user.business_id)
      else
        scope.none # Default to none if not manager/staff of a business
      end
    end
  end
end 