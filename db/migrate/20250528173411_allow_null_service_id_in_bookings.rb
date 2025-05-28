class AllowNullServiceIdInBookings < ActiveRecord::Migration[8.0]
  def up
    # Check if service_id is already nullable
    column = columns(:bookings).find { |c| c.name == 'service_id' }
    
    # Only change if it's currently NOT NULL
    if column && !column.null
      # Allow service_id to be null for orphaned bookings
      change_column_null :bookings, :service_id, true
    end
  end

  def down
    # Check if service_id is currently nullable
    column = columns(:bookings).find { |c| c.name == 'service_id' }
    
    # Only change if it's currently nullable
    if column && column.null
      # Restore NOT NULL constraint (will fail if orphaned bookings exist)
      change_column_null :bookings, :service_id, false
    end
  end
end
