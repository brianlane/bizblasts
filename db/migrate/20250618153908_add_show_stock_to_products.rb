class AddShowStockToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :show_stock_to_customers, :boolean, default: true, null: false
  end
end
