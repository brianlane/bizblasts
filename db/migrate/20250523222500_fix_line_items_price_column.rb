class FixLineItemsPriceColumn < ActiveRecord::Migration[8.0]
  def up
    # Rename unit_price to price if unit_price exists and price doesn't
    if column_exists?(:line_items, :unit_price) && !column_exists?(:line_items, :price)
      rename_column :line_items, :unit_price, :price
    end
    
    # If neither exists, add price column
    unless column_exists?(:line_items, :price) || column_exists?(:line_items, :unit_price)
      add_column :line_items, :price, :decimal, precision: 10, scale: 2
    end
  end
  
  def down
    # Rename back if needed
    if column_exists?(:line_items, :price) && !column_exists?(:line_items, :unit_price)
      rename_column :line_items, :price, :unit_price
    end
  end
end 