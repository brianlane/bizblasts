class RemoveBusinessTipsEnabled < ActiveRecord::Migration[8.0]
  def change
    remove_index :businesses, :tips_enabled
    remove_column :businesses, :tips_enabled, :boolean
  end
end 