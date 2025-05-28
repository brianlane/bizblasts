class AllowNullStaffMemberIdInBookings < ActiveRecord::Migration[8.0]
  def up
    # Check if staff_member_id is already nullable
    column = columns(:bookings).find { |c| c.name == 'staff_member_id' }
    
    # Only change if it's currently NOT NULL
    if column && !column.null
      # Allow staff_member_id to be null for orphaned bookings
      change_column_null :bookings, :staff_member_id, true
    end
  end

  def down
    # Check if staff_member_id is currently nullable
    column = columns(:bookings).find { |c| c.name == 'staff_member_id' }
    
    # Only change if it's currently nullable
    if column && column.null
      # Restore NOT NULL constraint (will fail if orphaned bookings exist)
      change_column_null :bookings, :staff_member_id, false
    end
  end
end
