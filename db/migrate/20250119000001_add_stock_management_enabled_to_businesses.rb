class AddStockManagementEnabledToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :stock_management_enabled, :boolean, default: true, null: false
    add_index :businesses, :stock_management_enabled
  end
end 