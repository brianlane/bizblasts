class AddPromotionFieldsToBookings < ActiveRecord::Migration[7.1]
  def change
    add_reference :bookings, :promotion, foreign_key: true
    add_column :bookings, :original_amount, :decimal, precision: 10, scale: 2
    add_column :bookings, :discount_amount, :decimal, precision: 10, scale: 2
    add_column :bookings, :amount, :decimal, precision: 10, scale: 2
  end
end
