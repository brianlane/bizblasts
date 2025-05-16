# frozen_string_literal: true

class CreateSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :subscriptions do |t|
      t.references :business, null: false, foreign_key: true
      t.string :plan_name, null: false
      t.string :stripe_subscription_id, null: false
      t.string :status, null: false
      t.datetime :current_period_end, null: false

      t.timestamps
    end

    add_index :subscriptions, :stripe_subscription_id, unique: true
    add_index :subscriptions, :business_id, unique: true # Assuming one active subscription per business in this table
  end
end
