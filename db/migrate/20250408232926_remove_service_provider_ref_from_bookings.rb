class RemoveServiceProviderRefFromBookings < ActiveRecord::Migration[7.1]
  def change
    remove_reference :bookings, :service_provider, null: false, foreign_key: { to_table: :staff_members }
  end
end
