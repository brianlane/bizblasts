class RemoveCategoryFromProducts < ActiveRecord::Migration[8.0]
  def up
    remove_foreign_key :products, :categories
    remove_index :products, :category_id
    remove_column :products, :category_id
  end
  
  def down
    add_column :products, :category_id, :bigint
    add_index :products, :category_id
    add_foreign_key :products, :categories
  end
end
