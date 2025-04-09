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

    private

    # Helper method to check if the user is an admin.
    # Assumes the user object is an AdminUser or responds to :admin?.
    def admin?
      user.present? # Basic check: is there a logged-in admin user?
    end
  end
end 