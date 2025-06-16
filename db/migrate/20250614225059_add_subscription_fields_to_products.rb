class AddSubscriptionFieldsToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :subscription_enabled, :boolean, default: false, null: false
    add_column :products, :subscription_discount_percentage, :decimal, precision: 5, scale: 2
    add_column :products, :subscription_billing_cycle, :string, default: 'monthly'
    add_column :products, :subscription_out_of_stock_action, :string, default: 'skip_billing_cycle'
  end
end
