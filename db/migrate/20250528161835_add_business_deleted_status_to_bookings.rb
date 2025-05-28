class AddBusinessDeletedStatusToBookings < ActiveRecord::Migration[8.0]
  def up
    # No database schema changes needed for adding enum values in Rails
    # The new business_deleted status (value 5) is handled in the model enum definition
    # This migration serves as documentation of the change
  end

  def down
    # Convert any business_deleted bookings to cancelled if rolling back
    execute <<-SQL
      UPDATE bookings SET status = 2 WHERE status = 5;
    SQL
  end
end
