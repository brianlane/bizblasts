class AddPaymentRemindersEnabledToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :payment_reminders_enabled, :boolean, default: false, null: false
  end
end
