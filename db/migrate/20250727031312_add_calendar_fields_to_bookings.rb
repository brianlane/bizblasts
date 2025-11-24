class AddCalendarFieldsToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :calendar_event_status, :integer, default: 0
    add_column :bookings, :calendar_event_id, :string
    
    add_index :bookings, :calendar_event_status
    add_index :bookings, :calendar_event_id
  end
end
