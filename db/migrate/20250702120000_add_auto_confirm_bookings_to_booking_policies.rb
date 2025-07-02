class AddAutoConfirmBookingsToBookingPolicies < ActiveRecord::Migration[6.1]
  def change
    add_column :booking_policies, :auto_confirm_bookings, :boolean, default: false, null: false
  end
end 