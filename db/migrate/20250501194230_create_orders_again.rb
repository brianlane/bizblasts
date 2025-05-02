class CreateOrdersAgain < ActiveRecord::Migration[7.0]
  def change
    create_table :orders do |t|
      t.references :tenant_customer, null: false, foreign_key: true
      t.references :shipping_method, null: true, foreign_key: true
      t.references :tax_rate, null: true, foreign_key: true
      t.string :order_number
      t.string :status
      t.decimal :total_amount, precision: 10, scale: 2
      t.decimal :tax_amount, precision: 10, scale: 2
      t.decimal :shipping_amount, precision: 10, scale: 2
      t.text :shipping_address
      t.text :billing_address
      t.text :notes
      t.references :business, null: false, foreign_key: true
      t.integer :order_type, default: 0
      
      t.timestamps
    end
    add_index :orders, [:business_id, :order_number], unique: true
  end
end
