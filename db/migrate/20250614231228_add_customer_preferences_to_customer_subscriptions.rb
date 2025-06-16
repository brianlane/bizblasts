class AddCustomerPreferencesToCustomerSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :customer_subscriptions, :customer_out_of_stock_preference, :string
    add_column :customer_subscriptions, :customer_rebooking_preference, :string
    add_column :customer_subscriptions, :allow_customer_preferences, :boolean, default: true, null: false
    
    add_index :customer_subscriptions, :customer_out_of_stock_preference
    add_index :customer_subscriptions, :customer_rebooking_preference
  end
end
