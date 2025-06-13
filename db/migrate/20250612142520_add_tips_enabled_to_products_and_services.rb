class AddTipsEnabledToProductsAndServices < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :tips_enabled, :boolean, default: false, null: false
    add_column :services, :tips_enabled, :boolean, default: false, null: false
    
    add_index :products, :tips_enabled
    add_index :services, :tips_enabled
  end
end 