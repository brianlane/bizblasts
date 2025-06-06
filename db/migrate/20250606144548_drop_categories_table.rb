class DropCategoriesTable < ActiveRecord::Migration[8.0]
  def up
    drop_table :categories
  end
  
  def down
    create_table :categories do |t|
      t.string :name, null: false
      t.references :business, null: false, foreign_key: true
      t.timestamps
    end
    add_index :categories, [:name, :business_id], unique: true
  end
end
