# frozen_string_literal: true

# Policy for CSV import/export operations.
# This is a "headless" policy - it authorizes based on user role,
# not a specific record.
class CsvPolicy < ApplicationPolicy
  # Allow managers and staff to view CSV import/export options
  def index?
    user_is_manager_or_staff?
  end

  # Allow managers and staff to export data
  def export?
    user_is_manager_or_staff?
  end

  # Only allow managers to import data (more destructive operation)
  def import?
    user_is_business_manager?
  end

  private

  def user_is_manager_or_staff?
    user.present? &&
      user.business_id.present? &&
      user.has_any_role?(:manager, :staff)
  end
end
