class FixPaymentsInvoiceConstraint < ActiveRecord::Migration[8.0]
  def up
    # Allow invoice_id to be null for orphaned payments
    change_column_null :payments, :invoice_id, true
    
    # Remove the existing foreign key constraint that prevents deletion
    remove_foreign_key :payments, :invoices
    
    # Add it back with nullify (we want to preserve payment history)
    # When invoice is deleted, we'll set invoice_id to null instead
    add_foreign_key :payments, :invoices, on_delete: :nullify
  end

  def down
    # Restore the original constraint
    remove_foreign_key :payments, :invoices
    add_foreign_key :payments, :invoices
    
    # Restore NOT NULL constraint (will fail if orphaned payments exist)
    change_column_null :payments, :invoice_id, false
  end
end
