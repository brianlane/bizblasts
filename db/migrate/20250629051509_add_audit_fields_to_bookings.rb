class AddAuditFieldsToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :cancelled_by, :integer
    add_column :bookings, :manager_override, :boolean
  end
end
