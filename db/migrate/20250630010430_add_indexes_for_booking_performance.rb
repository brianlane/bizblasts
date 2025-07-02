class AddIndexesForBookingPerformance < ActiveRecord::Migration[7.0]
  def change
    # Index for staff member booking queries (most common query)
    add_index :bookings, [:staff_member_id, :status], name: 'index_bookings_on_staff_member_and_status'
    
    # Index for time-based queries (availability checking)
    add_index :bookings, [:staff_member_id, :start_time, :end_time], name: 'index_bookings_on_staff_member_and_times'
    
    # Index for business tenant queries
    add_index :bookings, [:business_id, :staff_member_id], name: 'index_bookings_on_business_and_staff_member'
    
    # Index for daily booking limit queries
    add_index :bookings, [:staff_member_id, :start_time], name: 'index_bookings_on_staff_member_and_start_time'
    
    # Composite index for conflict detection queries
    add_index :bookings, [:staff_member_id, :status, :start_time, :end_time], 
              name: 'index_bookings_on_staff_status_and_times'
  end
end
