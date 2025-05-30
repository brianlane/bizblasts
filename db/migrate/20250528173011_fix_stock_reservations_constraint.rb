class FixStockReservationsConstraint < ActiveRecord::Migration[8.0]
  def up
    # First, clean up any orphaned stock_reservations that reference non-existent product_variants
    orphaned_count = execute(<<-SQL).cmd_tuples
      DELETE FROM stock_reservations 
      WHERE product_variant_id IS NOT NULL 
      AND product_variant_id NOT IN (SELECT id FROM product_variants)
    SQL
    
    if orphaned_count > 0
      puts "Cleaned up #{orphaned_count} orphaned stock_reservations"
    end
    
    # Check if the foreign key exists before trying to remove it
    if foreign_key_exists?(:stock_reservations, :product_variants)
      # Get the current foreign key to check if it already has cascade delete
      fk = foreign_keys(:stock_reservations).find { |fk| fk.to_table == 'product_variants' }
      
      # Only modify if it doesn't already have cascade delete
      if fk && fk.options[:on_delete] != :cascade
        # Remove the existing foreign key constraint
        remove_foreign_key :stock_reservations, :product_variants
        
        # Add it back with cascade delete
        add_foreign_key :stock_reservations, :product_variants, on_delete: :cascade
      end
    else
      # If no foreign key exists, add one with cascade delete
      add_foreign_key :stock_reservations, :product_variants, on_delete: :cascade
    end
  end

  def down
    # Check if the foreign key exists before trying to modify it
    if foreign_key_exists?(:stock_reservations, :product_variants)
      # Remove the cascade constraint and restore the original
      remove_foreign_key :stock_reservations, :product_variants
      add_foreign_key :stock_reservations, :product_variants
    end
  end
end
