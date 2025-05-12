# frozen_string_literal: true

module Settings
  class ProfilePolicy < ApplicationPolicy
    def edit?
      # A user can only edit their own profile
      user == record
    end

    def update?
      # A user can only update their own profile
      user == record
    end

    class Scope < Scope
      def resolve
        # Users can only see their own record in a profile context
        scope.where(id: user.id)
      end
    end
  end
end 