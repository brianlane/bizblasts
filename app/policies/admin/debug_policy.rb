# frozen_string_literal: true

# Policy for the custom ActiveAdmin Debug page.
module Admin
  class DebugPolicy < ApplicationPolicy
    # Allow admins to view the debug page.
    def index?
      admin?
    end

    # Debug page doesn't typically have a show action, but include for completeness.
    def show?
      index?
    end

    private

    # Helper method to check if the user is an admin.
    def admin?
      user.present?
    end
  end
end 