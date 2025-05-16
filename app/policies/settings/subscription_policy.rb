# frozen_string_literal: true

module Settings
  class SubscriptionPolicy < ApplicationPolicy
    attr_reader :user, :record # record is the subscription or a new subscription instance

    def initialize(user, record)
      @user = user
      @record = record # In this policy, record is often a Subscription instance or the Business itself
    end

    def show?
      # User must be a manager of the business associated with the subscription (or a potential subscription)
      user.manager? && user.business == target_business
    end

    def new?
      # User must be a manager of the business to initiate a new subscription
      user.manager? && user.business == target_business
    end

    def create_checkout_session? # Corresponds to the controller action
      new? # Same permissions as new?
    end

    def customer_portal_session? # Corresponds to the controller action for managing existing subscription
      show? # Same permissions as show?, needs an existing or potential subscription context
    end

    # Webhook is not managed by Pundit authorization as it's an external endpoint.

    private

    def target_business
      # record can be a Subscription instance (which has a business) or a Business instance itself
      # if controller passes Subscription.new(business: @business)
      record.is_a?(::Subscription) ? record.business : record
    end

    class Scope < Scope
      def resolve
        if user.manager?
          scope.where(business_id: user.business_id)
        else
          scope.none
        end
      end
    end
  end
end 