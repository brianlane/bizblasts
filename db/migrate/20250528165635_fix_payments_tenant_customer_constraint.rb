class FixPaymentsTenantCustomerConstraint < ActiveRecord::Migration[8.0]
  def up
    # Allow tenant_customer_id to be null for orphaned payments
    change_column_null :payments, :tenant_customer_id, true
    
    # Remove the existing foreign key constraint that prevents deletion
    remove_foreign_key :payments, :tenant_customers
    
    # Add it back without cascade delete (we want to preserve payment history)
    # When tenant_customer is deleted, we'll set tenant_customer_id to null instead
    add_foreign_key :payments, :tenant_customers, on_delete: :nullify
  end

  def down
    # Restore the original constraint
    remove_foreign_key :payments, :tenant_customers
    add_foreign_key :payments, :tenant_customers
    
    # Restore NOT NULL constraint (will fail if orphaned payments exist)
    change_column_null :payments, :tenant_customer_id, false
  end
end
