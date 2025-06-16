class AddPausedAtToCustomerSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :customer_subscriptions, :paused_at, :datetime
  end
end
