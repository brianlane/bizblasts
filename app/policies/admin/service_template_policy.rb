# frozen_string_literal: true

# Policy for managing ServiceTemplate resources within the ActiveAdmin interface.
module Admin
  class ServiceTemplatePolicy < ApplicationPolicy
    class Scope < ApplicationPolicy::Scope
      def resolve
        admin? ? scope.all : scope.none
      end
    end
    # Add specific rules here if needed, otherwise inherits defaults

    # Required for member actions like publish, unpublish, etc.
    def publish?
      admin?
    end

    def unpublish?
      admin?
    end

    def activate?
      admin?
    end

    def deactivate?
      admin?
    end
  end
end 