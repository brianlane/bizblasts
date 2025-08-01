class AddDefaultCalendarConnectionToStaffMembers < ActiveRecord::Migration[8.0]
  def change
    add_reference :staff_members, :default_calendar_connection, null: true, foreign_key: { to_table: :calendar_connections }
  end
end
