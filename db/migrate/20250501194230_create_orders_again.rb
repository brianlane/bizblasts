class CreateOrdersAgain < ActiveRecord::Migration[8.0]
  def change
    create_table :orders do |t|
      t.references :tenant_customer, null: false, foreign_key: true
      t.string :order_number, null: false
      t.string :status, null: false, default: 'pending'
      t.decimal :total_amount, precision: 10, scale: 2, null: false
      t.decimal :shipping_amount, precision: 10, scale: 2, default: 0
      t.decimal :tax_amount, precision: 10, scale: 2, default: 0
      t.references :shipping_method, foreign_key: true # Optional
      t.references :tax_rate, foreign_key: true # Optional
      t.references :business, null: false, foreign_key: true
      # Add any other necessary fields like billing/shipping address, notes, etc.
      t.text :shipping_address
      t.text :billing_address
      t.text :notes

      t.timestamps
    end
    add_index :orders, :order_number, unique: true
    add_index :orders, :status
  end
end
