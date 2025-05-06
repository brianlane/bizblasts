class AddStockQuantityToProducts < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:products, :stock_quantity)
      add_column :products, :stock_quantity, :integer, default: 0, null: false
    end
  end
end
