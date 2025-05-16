# frozen_string_literal: true

class AddStripeCustomerIdToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :stripe_customer_id, :string
    add_index :businesses, :stripe_customer_id, unique: true
  end
end
