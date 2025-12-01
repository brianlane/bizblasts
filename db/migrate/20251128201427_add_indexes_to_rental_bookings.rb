class AddIndexesToRentalBookings < ActiveRecord::Migration[8.1]
  def change
    # Composite index for business and status filtering
    add_index :rental_bookings, [:business_id, :status],
      name: 'index_rental_bookings_on_business_and_status',
      if_not_exists: true

    # Composite index for product availability queries
    add_index :rental_bookings, [:product_id, :start_time, :end_time],
      name: 'index_rental_bookings_on_product_and_times',
      if_not_exists: true

    # Partial index for overdue rentals (only checked_out and overdue statuses)
    add_index :rental_bookings, :end_time,
      where: "status IN ('checked_out', 'overdue')",
      name: 'index_rental_bookings_on_end_time_for_overdue',
      if_not_exists: true

    # Index for Stripe payment intent lookups
    add_index :rental_bookings, :stripe_deposit_payment_intent_id,
      name: 'index_rental_bookings_on_stripe_payment_intent',
      if_not_exists: true

    # Index for guest access token lookups
    add_index :rental_bookings, :guest_access_token,
      name: 'index_rental_bookings_on_guest_access_token',
      if_not_exists: true

    # Index for booking number lookups (unique)
    add_index :rental_bookings, [:business_id, :booking_number],
      unique: true,
      name: 'index_rental_bookings_on_business_and_booking_number',
      if_not_exists: true
  end
end
