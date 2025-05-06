class AddStockQuantityToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :stock_quantity, :integer, default: 0, null: false
  end
end
