class AddCancellationReasonToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :cancellation_reason, :text
  end
end
