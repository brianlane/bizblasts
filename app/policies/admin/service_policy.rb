# frozen_string_literal: true

# Policy for managing Service resources within the ActiveAdmin interface.
module Admin
  class ServicePolicy < ApplicationPolicy
    class Scope < ApplicationPolicy::Scope
      def resolve
        admin? ? scope.all : scope.none
      end
    end
    # Add specific rules here if needed, otherwise inherits defaults
  end
end 