class CreateServiceVariants < ActiveRecord::Migration[8.0]
  def change
    create_table :service_variants do |t|
      t.references :service, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :duration, null: false
      t.decimal :price, precision: 10, scale: 2, null: false
      t.boolean :active, default: true
      t.integer :position, default: 0
      t.timestamps
    end

    add_index :service_variants, [:service_id, :name], unique: true
  end
end 