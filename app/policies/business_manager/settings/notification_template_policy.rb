module BusinessManager
  module Settings
    class NotificationTemplatePolicy < ApplicationPolicy
      def index?
        authorized = user_is_business_manager?
        log_authorization_failure(:index) unless authorized
        authorized
      end

      def show?
        authorized = user_is_business_manager? && record_belongs_to_user_business?
        log_authorization_failure(:show) unless authorized
        authorized
      end

      def create?
        authorized = user_is_business_manager?
        log_authorization_failure(:create) unless authorized
        authorized
      end

      def new?
        create?
      end

      def update?
        authorized = user_is_business_manager? && record_belongs_to_user_business?
        log_authorization_failure(:update) unless authorized
        authorized
      end

      def edit?
        update?
      end

      def destroy?
        authorized = user_is_business_manager? && record_belongs_to_user_business?
        log_authorization_failure(:destroy) unless authorized
        authorized
      end

      class Scope < Scope
        def resolve
          scope.where(business: user.business)
        end
      end
    end
  end
end 