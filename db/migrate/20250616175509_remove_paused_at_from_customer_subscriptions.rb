class RemovePausedAtFromCustomerSubscriptions < ActiveRecord::Migration[8.0]
  def change
    remove_column :customer_subscriptions, :paused_at, :datetime
  end
end
