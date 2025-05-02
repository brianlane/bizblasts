class CreateProductsAgain < ActiveRecord::Migration[8.0]
  def change
    create_table :products do |t|
      t.string :name, null: false
      t.text :description
      t.decimal :price, precision: 10, scale: 2, null: false
      t.boolean :active, default: true
      t.boolean :featured, default: false
      t.references :category, foreign_key: true # Optional association
      t.references :business, null: false, foreign_key: true
      # If products without variants need stock tracking:
      # t.integer :stock_quantity, default: 0, null: false

      t.timestamps
    end
  end
end
