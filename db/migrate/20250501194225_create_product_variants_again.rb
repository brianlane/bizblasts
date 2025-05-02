class CreateProductVariantsAgain < ActiveRecord::Migration[8.0]
  def change
    create_table :product_variants do |t|
      t.references :product, null: false, foreign_key: true
      t.string :name, null: false
      t.decimal :price_modifier, precision: 10, scale: 2 # Can be nil, positive, or negative
      t.integer :stock_quantity, default: 0, null: false

      t.timestamps
    end
    # Add index if variants need to be unique per product (e.g., based on name)
    # add_index :product_variants, [:product_id, :name], unique: true
  end
end
