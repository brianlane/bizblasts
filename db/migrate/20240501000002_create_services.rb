class CreateServices < ActiveRecord::Migration[8.0]
  def change
    create_table :services do |t|
      t.string :name, null: false
      t.text :description
      t.integer :duration, null: false
      t.decimal :price, precision: 10, scale: 2, null: false
      t.boolean :active, default: true
      t.references :business, null: false, foreign_key: true
      
      t.timestamps
    end
    
    add_index :services, [:name, :business_id], unique: true
  end
end
