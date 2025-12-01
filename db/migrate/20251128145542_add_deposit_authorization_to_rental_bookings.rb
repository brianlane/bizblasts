# frozen_string_literal: true

class AddDepositAuthorizationToRentalBookings < ActiveRecord::Migration[8.1]
  def change
    # Track whether deposit is authorized (held) vs captured (charged)
    add_column :rental_bookings, :deposit_authorization_id, :string
    add_column :rental_bookings, :deposit_authorized_at, :datetime
    add_column :rental_bookings, :deposit_captured_at, :datetime
    add_column :rental_bookings, :deposit_authorization_released_at, :datetime
    
    add_index :rental_bookings, :deposit_authorization_id,
      name: 'index_rental_bookings_on_deposit_authorization_id'
  end
end
