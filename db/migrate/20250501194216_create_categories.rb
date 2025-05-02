class CreateCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :categories do |t|
      t.string :name, null: false
      t.references :business, null: false, foreign_key: true

      t.timestamps
    end
    add_index :categories, [:name, :business_id], unique: true
  end
end
