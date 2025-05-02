class CreateLineItemsAgain < ActiveRecord::Migration[8.0]
  def change
    create_table :line_items do |t|
      t.references :lineable, polymorphic: true, null: false
      t.references :product_variant, null: false, foreign_key: true
      t.integer :quantity, null: false
      t.decimal :price, precision: 10, scale: 2, null: false # Price per unit at the time of addition
      t.decimal :total_amount, precision: 10, scale: 2, null: false # quantity * price
      # Add name/description snapshot if needed
      # t.string :product_name
      # t.string :variant_name

      t.timestamps
    end
  end
end
