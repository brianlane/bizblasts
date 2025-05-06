class CreateStockReservations < ActiveRecord::Migration[8.0]
  def change
    create_table :stock_reservations do |t|
      t.bigint :product_variant_id
      t.bigint :order_id
      t.integer :quantity
      t.datetime :expires_at

      t.timestamps
    end
  end
end
