module BusinessManager
  module Settings
    class LocationPolicy < ApplicationPolicy
      def index?
        user.manager?
      end

      def show?
        user.manager?
      end

      def create?
        user.manager?
      end

      def new?
        create?
      end

      def update?
        user.manager?
      end

      def edit?
        update?
      end

      def destroy?
        user.manager?
      end

      def edit_credentials?
        user.manager?
      end

      class Scope < Scope
        def resolve
          scope.where(business: user.business)
        end
      end
    end
  end
end 