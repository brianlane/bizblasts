# frozen_string_literal: true

# Defines authorization rules for Service resources.
# Inherits defaults from BusinessPolicy, but overrides actions based on user role within their business.
class ServicePolicy < BusinessPolicy # Inherit from the global BusinessPolicy
  # Standard Pundit initializer
  # user: Currently logged-in user
  # record: The object being authorized (Service instance, Service class, or scope)
  # attr_reader :user, :record # Already provided by ApplicationPolicy/Pundit

  # initialize(user, record) - Handled by inheritance

  # Can the user see the list of services for their business? (Managers & Staff)
  def index?
    # User must belong to a business and be manager or staff
    user.present? && user.business_id.present? && user.has_any_role?(:manager, :staff)
  end

  # Can the user view the form to create a new service? (Managers only)
  def new?
    create?
  end

  # Can the user create a new service for their business? (Managers only)
  def create?
    user.present? && user.business_id.present? && user.manager?
  end

  # Can the user view the form to edit an existing service? (Managers only)
  # record is the Service instance here.
  def edit?
    update?
  end

  # Can the user update an existing service belonging to their business? (Managers only)
  # record is the Service instance here.
  def update?
    # User must be manager, and service must belong to the user's business
    user.present? && user.manager? && record.present? && record.business_id == user.business_id
  end

  # Can the user delete an existing service belonging to their business? (Managers only)
  # record is the Service instance here.
  def destroy?
    # User must be manager, and service must belong to the user's business
    user.present? && user.manager? && record.present? && record.business_id == user.business_id
  end

  # Scope class to filter services based on user role and business tenancy.
  class Scope < Scope # Inherit from BusinessPolicy::Scope which inherits from ApplicationPolicy::Scope
    # Standard Pundit scope initializer
    # user: Currently logged-in user
    # scope: The base scope (e.g., Service.all)
    # attr_reader :user, :scope # Provided by ApplicationPolicy::Scope

    # initialize(user, scope) - Handled by inheritance

    # Resolve the scope:
    # - Managers/Staff see services for their business.
    # - Others (including admins for now, unless BusinessPolicy::Scope handles admins) see none within this specific policy.
    def resolve
      if user.present? && user.business_id.present? && user.has_any_role?(:manager, :staff)
        # Scope services to the user's current business
        scope.where(business_id: user.business_id)
      else
        scope.none # Default to none if not manager/staff of a business
        # Consider if admin should see all - depends on inheritance from BusinessPolicy::Scope
      end
    end
  end

  # Removed private helpers that relied on custom @business ivar
  # private
  # def user_belongs_to_business?
  # def record_belongs_to_business?
end 