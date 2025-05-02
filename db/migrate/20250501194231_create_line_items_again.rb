class CreateLineItemsAgain < ActiveRecord::Migration[7.0]
  def change
    create_table :line_items do |t|
      t.references :lineable, polymorphic: true, null: false
      t.integer :quantity
      t.decimal :unit_price, precision: 10, scale: 2
      t.decimal :total_amount, precision: 10, scale: 2
      t.references :order, null: false, foreign_key: true

      t.timestamps
    end
  end
end
