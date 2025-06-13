class AddTipReminderSentAtToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :tip_reminder_sent_at, :datetime
  end
end
