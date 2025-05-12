# frozen_string_literal: true

module Settings
  class TeamPolicy < ApplicationPolicy
    # List all team members for a business (manager or staff)
    def index?
      user.present? && user.business_id.present? && user.has_any_role?(:manager, :staff)
    end

    # Only managers can invite new team members
    def new?
      user.present? && user.business_id.present? && user.manager?
    end
    def create?
      new?
    end

    # Only managers can remove team members of their own business
    def destroy?
      user.present? && user.manager? && record.present? && record.business_id == user.business_id
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
end 