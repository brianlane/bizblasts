# frozen_string_literal: true

# Defines authorization rules for RentalBooking resources.
# Inherits defaults from BusinessPolicy
class RentalBookingPolicy < BusinessPolicy
  # Can the user see the list of rental bookings for their business? (Managers & Staff)
  def index?
    user.present? && user.business_id.present? && user.has_any_role?(:manager, :staff)
  end

  # Can the user view a specific rental booking? (Managers & Staff)
  def show?
    user.present? && user.business_id.present? && user.has_any_role?(:manager, :staff) &&
      record.present? && record.business_id == user.business_id
  end

  # Can the user view the form to create a new rental booking? (Managers & Staff)
  def new?
    create?
  end

  # Can the user create a new rental booking for their business? (Managers & Staff)
  def create?
    user.present? && user.business_id.present? && user.has_any_role?(:manager, :staff)
  end

  # Can the user view the form to edit an existing rental booking? (Managers only - before checkout)
  def edit?
    update?
  end

  # Can the user update an existing rental booking? (Managers only - before checkout)
  def update?
    user.present? && user.manager? && record.present? && record.business_id == user.business_id
  end

  # Can the user check out a rental? (Managers & Staff)
  def check_out?
    user.present? && user.has_any_role?(:manager, :staff) &&
      record.present? && record.business_id == user.business_id &&
      record.can_check_out?
  end

  # Can the user process a return? (Managers & Staff)
  def process_return?
    user.present? && user.has_any_role?(:manager, :staff) &&
      record.present? && record.business_id == user.business_id &&
      record.can_return?
  end

  # Can the user complete a rental? (Managers only)
  def complete?
    user.present? && user.manager? &&
      record.present? && record.business_id == user.business_id
  end

  # Can the user cancel a rental booking? (Managers only)
  def cancel?
    user.present? && user.manager? &&
      record.present? && record.business_id == user.business_id &&
      record.can_cancel?
  end

  # Can the user view the rental calendar? (Managers & Staff)
  def calendar?
    user.present? && user.business_id.present? && user.has_any_role?(:manager, :staff)
  end

  # Can the user view overdue rentals? (Managers & Staff)
  def overdue?
    user.present? && user.business_id.present? && user.has_any_role?(:manager, :staff)
  end

  # Scope class to filter rental bookings based on user role and business tenancy
  class Scope < Scope
    def resolve
      if user.present? && user.business_id.present? && user.has_any_role?(:manager, :staff)
        # Scope rental bookings to the user's current business
        scope.where(business_id: user.business_id)
      else
        scope.none # Default to none if not manager/staff of a business
      end
    end
  end
end
