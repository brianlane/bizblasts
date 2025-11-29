class AddLockVersionToRentalBookings < ActiveRecord::Migration[8.1]
  def change
    add_column :rental_bookings, :lock_version, :integer, default: 0, null: false
  end
end
