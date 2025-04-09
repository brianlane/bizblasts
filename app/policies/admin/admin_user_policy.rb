# frozen_string_literal: true

# Policy for managing AdminUser resources within the ActiveAdmin interface.
module Admin
  class AdminUserPolicy < ApplicationPolicy
    class Scope < ApplicationPolicy::Scope
      def resolve
        admin? ? scope.all : scope.none
      end
    end
    # Add specific rules here if needed, otherwise inherits defaults
  end
end 