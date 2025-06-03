# frozen_string_literal: true

class InvoicePolicy < BusinessPolicy
  # Managers and staff can list invoices
  def index?
    user.present? && user.business_id.present? && user.has_any_role?(:manager, :staff)
  end

  # Can view a specific invoice if it belongs to their business
  def show?
    user.present? && user.business_id.present? && user.has_any_role?(:manager, :staff) && record.business_id == user.business_id
  end

  # Can resend invoice to customer
  def resend?
    show?
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