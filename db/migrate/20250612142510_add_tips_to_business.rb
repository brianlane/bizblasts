class AddTipsToBusiness < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :tips_enabled, :boolean, default: false, null: false
    add_index :businesses, :tips_enabled
  end
end
