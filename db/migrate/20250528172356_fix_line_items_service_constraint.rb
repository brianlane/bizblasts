class FixLineItemsServiceConstraint < ActiveRecord::Migration[8.0]
  def up
    # Allow service_id to be null for orphaned line items
    change_column_null :line_items, :service_id, true
    
    # Remove the existing foreign key constraint that prevents deletion
    remove_foreign_key :line_items, :services
    
    # Add it back with nullify (we want to preserve line item history)
    # When service is deleted, we'll set service_id to null instead
    add_foreign_key :line_items, :services, on_delete: :nullify
  end

  def down
    # Restore the original constraint
    remove_foreign_key :line_items, :services
    add_foreign_key :line_items, :services
    
    # Restore NOT NULL constraint (will fail if orphaned line items exist)
    change_column_null :line_items, :service_id, false
  end
end
