class CreateShippingMethodsAgain < ActiveRecord::Migration[8.0]
  def change
    create_table :shipping_methods do |t|
      t.string :name, null: false
      t.decimal :cost, precision: 10, scale: 2, null: false, default: 0
      t.boolean :active, default: true
      t.references :business, null: false, foreign_key: true

      t.timestamps
    end
    add_index :shipping_methods, [:name, :business_id], unique: true
  end
end
