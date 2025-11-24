class AddStripeConnectReminderSentAtToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :stripe_connect_reminder_sent_at, :datetime
  end
end
