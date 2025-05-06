class AddStockQuantityToProducts < ActiveRecord::Migration[8.0]
  def change
    # Skip if the table doesn't exist yet
    return unless table_exists?(:products)
    
    unless column_exists?(:products, :stock_quantity)
      add_column :products, :stock_quantity, :integer, default: 0, null: false
    end
  end
end
