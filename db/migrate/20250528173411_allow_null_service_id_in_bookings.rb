class AllowNullServiceIdInBookings < ActiveRecord::Migration[8.0]
  def up
    # Allow service_id to be null for orphaned bookings
    change_column_null :bookings, :service_id, true
  end

  def down
    # Restore NOT NULL constraint (will fail if orphaned bookings exist)
    change_column_null :bookings, :service_id, false
  end
end
