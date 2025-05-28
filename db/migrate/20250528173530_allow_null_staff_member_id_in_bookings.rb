class AllowNullStaffMemberIdInBookings < ActiveRecord::Migration[8.0]
  def up
    # Allow staff_member_id to be null for orphaned bookings
    change_column_null :bookings, :staff_member_id, true
  end

  def down
    # Restore NOT NULL constraint (will fail if orphaned bookings exist)
    change_column_null :bookings, :staff_member_id, false
  end
end
