module BusinessManager
  module Settings
    class IntegrationPolicy < ApplicationPolicy
      def index?
        user.manager?
      end

      def show?
        user.manager? && record.business_id == user.business.id
      end

      def create?
        user.manager?
      end

      def new?
        create?
      end

      def update?
        user.manager? && record.business_id == user.business.id
      end

      def edit?
        update?
      end

      def destroy?
        user.manager? && record.business_id == user.business.id
      end

      class Scope < Scope
        def resolve
          scope.where(business: user.business)
        end
      end
    end
  end
end 