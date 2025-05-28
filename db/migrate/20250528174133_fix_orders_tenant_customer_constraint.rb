class FixOrdersTenantCustomerConstraint < ActiveRecord::Migration[8.0]
  def up
    # Remove the existing foreign key constraint
    remove_foreign_key :orders, :tenant_customers
    
    # Make tenant_customer_id nullable for orphaned orders
    change_column_null :orders, :tenant_customer_id, true
    
    # Add the foreign key constraint with on_delete: :nullify
    add_foreign_key :orders, :tenant_customers, on_delete: :nullify
  end

  def down
    # Remove the updated foreign key constraint
    remove_foreign_key :orders, :tenant_customers
    
    # Make tenant_customer_id not nullable again (this might fail if there are null values)
    change_column_null :orders, :tenant_customer_id, false
    
    # Restore the original foreign key constraint (without on_delete)
    add_foreign_key :orders, :tenant_customers
  end
end
