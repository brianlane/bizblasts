class AddCustomerPreferencesJsonToCustomerSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :customer_subscriptions, :customer_preferences, :json
  end
end
