class AddCustomerRebookingOptionsToCustomerSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :customer_subscriptions, :customer_rebooking_option, :string
  end
end
