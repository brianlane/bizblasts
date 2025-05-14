class AddTypeAndBookingFieldsToServices < ActiveRecord::Migration[8.0]
  def change
    add_column :services, :type, :integer
    add_column :services, :min_bookings, :integer
    add_column :services, :max_bookings, :integer
    add_column :services, :spots, :integer
  end
end
