# frozen_string_literal: true

module BusinessManager::Settings
  class BookingPolicyPolicy < ApplicationPolicy
    attr_reader :user, :booking_policy

    def initialize(user, booking_policy)
      @user = user
      @booking_policy = booking_policy
    end

    def show?
      manager?
    end

    def edit?
      manager?
    end

    def update?
      manager?
    end

    private

    # Assuming user has a method like manager? or roles associated with the business
    # Or check via staff_member association
    def manager?
      user.present? && user.staff_member_for(booking_policy.business)&.manager?
      # Adjust the check based on your actual authorization logic (e.g., roles)
    end

    # Scope class for index pages if needed later
    # class Scope < Scope
    #   def resolve
    #     # Define scope logic here if listing multiple policies were possible
    #     scope.none # Example: No index view currently
    #   end
    # end
  end
end 