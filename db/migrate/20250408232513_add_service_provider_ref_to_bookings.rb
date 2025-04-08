class AddServiceProviderRefToBookings < ActiveRecord::Migration[7.1]
  def change
    add_reference :bookings, :service_provider, null: false, foreign_key: { to_table: :staff_members }
  end
end
