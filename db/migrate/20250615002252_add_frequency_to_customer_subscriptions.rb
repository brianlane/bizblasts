class AddFrequencyToCustomerSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :customer_subscriptions, :frequency, :string, null: false, default: 'monthly'
    add_index :customer_subscriptions, :frequency
  end
end
