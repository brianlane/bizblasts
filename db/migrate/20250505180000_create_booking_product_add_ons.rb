class CreateBookingProductAddOns < ActiveRecord::Migration[8.0]
  def change
    create_table :booking_product_add_ons do |t|
      t.references :booking, null: false, foreign_key: true
      t.references :product_variant, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1
      t.decimal :price, precision: 10, scale: 2, null: false
      t.decimal :total_amount, precision: 10, scale: 2, null: false
      t.timestamps
    end
  end
end 