class UpdateRentalBookingNumberIndex < ActiveRecord::Migration[8.1]
  def change
    if index_exists?(:rental_bookings, :booking_number)
      remove_index :rental_bookings, :booking_number
    end

    add_index :rental_bookings,
              [:business_id, :booking_number],
              unique: true,
              name: 'index_rental_bookings_on_business_and_booking_number',
              if_not_exists: true
  end
end

