# frozen_string_literal: true

class FixSubscriptionsBusinessIndexUnique < ActiveRecord::Migration[8.0]
  def up
    # As per db/schema.rb, the existing index is:
    # t.index ["business_id"], name: "index_subscriptions_on_business_id"
    # This implies it is NOT unique.

    # Remove the non-unique index if it exists by its known name from schema.rb
    if index_exists?(:subscriptions, :business_id, name: "index_subscriptions_on_business_id")
      # Verify it is indeed non-unique before removing, to be safe
      idx = ActiveRecord::Base.connection.indexes(:subscriptions).find { |i| i.name == "index_subscriptions_on_business_id" }
      if idx && !idx.unique
        remove_index :subscriptions, name: "index_subscriptions_on_business_id"
      end
    end

    # Add the unique index
    unless index_exists?(:subscriptions, :business_id, unique: true)
      add_index :subscriptions, :business_id, unique: true
    end
  end

  def down
    # If we roll back, we want to restore the non-unique index and remove the unique one.
    if index_exists?(:subscriptions, :business_id, unique: true)
      remove_index :subscriptions, :business_id, unique: true
    end

    unless index_exists?(:subscriptions, :business_id, name: "index_subscriptions_on_business_id")
      add_index :subscriptions, :business_id, name: "index_subscriptions_on_business_id" # non-unique
    end
  end
end

