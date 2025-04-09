# frozen_string_literal: true

# Policy for the main ActiveAdmin Dashboard page.
module Admin
  class DashboardPolicy < ApplicationPolicy
    # Allow admins to view the dashboard.
    def index?
      admin?
    end

    # Dashboard doesn't typically have a show action, but include for completeness.
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