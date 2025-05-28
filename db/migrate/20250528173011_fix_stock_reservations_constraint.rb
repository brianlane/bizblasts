class FixStockReservationsConstraint < ActiveRecord::Migration[8.0]
  def up
    # Remove the existing foreign key constraint that prevents deletion
    remove_foreign_key :stock_reservations, :product_variants
    
    # Add it back with cascade delete (stock reservations should be deleted when product variant is deleted)
    add_foreign_key :stock_reservations, :product_variants, on_delete: :cascade
  end

  def down
    # Restore the original constraint
    remove_foreign_key :stock_reservations, :product_variants
    add_foreign_key :stock_reservations, :product_variants
  end
end
