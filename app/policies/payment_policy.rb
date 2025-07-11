# frozen_string_literal: true

class PaymentPolicy < ApplicationPolicy
  def index?
    user_can_access_business_manager?
  end

  def show?
    user_can_access_business_manager? && payment_belongs_to_business?
  end

  private

  def user_can_access_business_manager?
    user.present? && (user.manager? || user.admin?)
  end

  def payment_belongs_to_business?
    record.business == user.business
  end

  class Scope < Scope
    def resolve
      if user.admin?
        scope.all
      elsif user.manager?
        scope.where(business: user.business)
      else
        scope.none
      end
    end
  end
end 