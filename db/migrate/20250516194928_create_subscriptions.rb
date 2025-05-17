# frozen_string_literal: true

class CreateSubscriptions < ActiveRecord::Migration[8.0]
  def change
    if !table_exists?(:subscriptions)
      create_table :subscriptions do |t|
        t.references :business, null: false, foreign_key: true
        t.string :plan_name, null: false
        t.string :stripe_subscription_id, null: false
        t.string :status, null: false
        t.datetime :current_period_end, null: false

        t.timestamps
      end

      # Only add these indexes if they don't already exist
      unless index_exists?(:subscriptions, :stripe_subscription_id, name: "index_subscriptions_on_stripe_subscription_id")
        add_index :subscriptions, :stripe_subscription_id, unique: true, if_not_exists: true
      end
      
      unless index_exists?(:subscriptions, :business_id, name: "index_subscriptions_on_business_id")
        add_index :subscriptions, :business_id, unique: true, if_not_exists: true
      end
    end
  end
end
