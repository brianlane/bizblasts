# frozen_string_literal: true

# Policy for managing Business resources within the ActiveAdmin interface.
# Currently allows all actions for any logged-in admin user.
# TODO: Implement more granular permissions if needed.
module Admin
  class BusinessPolicy < ApplicationPolicy
    # Scope class for filtering Business records.
    # Currently allows access to all businesses.
    class Scope < ApplicationPolicy::Scope
      def resolve
        scope.all
      end
    end

    def index?
      admin?
    end

    def show?
      admin?
    end

    def create?
      admin?
    end

    def new?
      create?
    end

    def update?
      admin?
    end

    def edit?
      update?
    end

    def destroy?
      admin?
    end

    # Custom domain management member actions
    def start_domain_setup?
      admin?
    end

    def restart_domain_monitoring?
      admin?
    end

    def force_activate_domain?
      admin?
    end

    def disable_custom_domain?
      admin?
    end

    def domain_status?
      admin?
    end

    private

    # Helper method to check if the user is an admin.
    # Ensures user is actually an AdminUser instance for security
    def admin?
      user.is_a?(AdminUser)
    end
  end
end 