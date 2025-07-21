class AddServiceVariantToBookings < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:bookings, :service_variant_id)
      add_reference :bookings, :service_variant, foreign_key: true
    end
  end
end 