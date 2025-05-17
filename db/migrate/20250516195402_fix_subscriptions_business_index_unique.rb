# frozen_string_literal: true

class FixSubscriptionsBusinessIndexUnique < ActiveRecord::Migration[8.0]
  def up
    # Only attempt to fix the indexes if the subscriptions table exists
    return unless table_exists?(:subscriptions)

    # Remove the non-unique index if it exists by its known name from schema.rb
    if index_exists?(:subscriptions, :business_id, name: "index_subscriptions_on_business_id")
      # Verify it is indeed non-unique before removing, to be safe
      idx = ActiveRecord::Base.connection.indexes(:subscriptions).find { |i| i.name == "index_subscriptions_on_business_id" }
      if idx && !idx.unique
        remove_index :subscriptions, name: "index_subscriptions_on_business_id", if_exists: true
      end
    end

    # Add the unique index, but only if there isn't already a unique index on business_id
    unless index_exists?(:subscriptions, :business_id, unique: true)
      add_index :subscriptions, :business_id, unique: true, if_not_exists: true
    end

    # Same for stripe_subscription_id
    if index_exists?(:subscriptions, :stripe_subscription_id, name: "index_subscriptions_on_stripe_subscription_id")
      idx = ActiveRecord::Base.connection.indexes(:subscriptions).find { |i| i.name == "index_subscriptions_on_stripe_subscription_id" }
      if idx && !idx.unique
        remove_index :subscriptions, name: "index_subscriptions_on_stripe_subscription_id", if_exists: true
      end
    end

    unless index_exists?(:subscriptions, :stripe_subscription_id, unique: true)
      add_index :subscriptions, :stripe_subscription_id, unique: true, if_not_exists: true
    end
  end

  def down
    # If we roll back, we want to restore the non-unique index and remove the unique one.
    # But only if the table exists
    return unless table_exists?(:subscriptions)

    if index_exists?(:subscriptions, :business_id, unique: true)
      remove_index :subscriptions, :business_id, unique: true, if_exists: true
    end

    unless index_exists?(:subscriptions, :business_id, name: "index_subscriptions_on_business_id")
      add_index :subscriptions, :business_id, name: "index_subscriptions_on_business_id", if_not_exists: true
    end

    # Same for stripe_subscription_id
    if index_exists?(:subscriptions, :stripe_subscription_id, unique: true)
      remove_index :subscriptions, :stripe_subscription_id, unique: true, if_exists: true
    end

    unless index_exists?(:subscriptions, :stripe_subscription_id, name: "index_subscriptions_on_stripe_subscription_id")
      add_index :subscriptions, :stripe_subscription_id, name: "index_subscriptions_on_stripe_subscription_id", if_not_exists: true
    end
  end
end

