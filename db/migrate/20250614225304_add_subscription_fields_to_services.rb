class AddSubscriptionFieldsToServices < ActiveRecord::Migration[8.0]
  def change
    add_column :services, :subscription_enabled, :boolean, default: false, null: false
    add_column :services, :subscription_discount_percentage, :decimal, precision: 5, scale: 2
    add_column :services, :subscription_billing_cycle, :string, default: 'monthly'
    add_column :services, :subscription_rebooking_preference, :string, default: 'same_day_next_month'
  end
end
