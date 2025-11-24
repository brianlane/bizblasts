class CreateUserSidebarItems < ActiveRecord::Migration[8.0]
  def change
    create_table :user_sidebar_items do |t|
      t.references :user, null: false, foreign_key: true
      t.string :item_key, null: false
      t.integer :position, null: false, default: 0
      t.boolean :visible, null: false, default: true
      t.timestamps
    end
    add_index :user_sidebar_items, [:user_id, :item_key], unique: true
  end
end 