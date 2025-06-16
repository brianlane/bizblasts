class CreateStockMovements < ActiveRecord::Migration[8.0]
  def change
    create_table :stock_movements do |t|
      t.references :product, null: false, foreign_key: true
      t.integer :quantity
      t.string :movement_type
      t.string :reference_id
      t.string :reference_type
      t.text :notes

      t.timestamps
    end
  end
end
