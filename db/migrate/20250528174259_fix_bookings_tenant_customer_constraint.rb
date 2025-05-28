class FixBookingsTenantCustomerConstraint < ActiveRecord::Migration[8.0]
  def up
    # Check if tenant_customer_id is already nullable
    column = columns(:bookings).find { |c| c.name == 'tenant_customer_id' }
    
    # Make tenant_customer_id nullable if it isn't already
    if column && !column.null
      change_column_null :bookings, :tenant_customer_id, true
    end
    
    # Check if the foreign key exists and has the correct constraint
    if foreign_key_exists?(:bookings, :tenant_customers)
      fk = foreign_keys(:bookings).find { |fk| fk.to_table == 'tenant_customers' }
      
      # Only modify if it doesn't already have nullify
      if fk && fk.options[:on_delete] != :nullify
        # Remove the existing foreign key constraint
        remove_foreign_key :bookings, :tenant_customers
        
        # Add the foreign key constraint with on_delete: :nullify
        add_foreign_key :bookings, :tenant_customers, on_delete: :nullify
      end
    else
      # If no foreign key exists, add one with nullify
      add_foreign_key :bookings, :tenant_customers, on_delete: :nullify
    end
  end

  def down
    # Check if the foreign key exists before trying to modify it
    if foreign_key_exists?(:bookings, :tenant_customers)
      # Remove the updated foreign key constraint
      remove_foreign_key :bookings, :tenant_customers
      
      # Restore the original foreign key constraint (without on_delete)
      add_foreign_key :bookings, :tenant_customers
    end
    
    # Check if tenant_customer_id is currently nullable
    column = columns(:bookings).find { |c| c.name == 'tenant_customer_id' }
    
    # Only change if it's currently nullable and there are no null values
    if column && column.null
      # Make tenant_customer_id not nullable again (this might fail if there are null values)
      change_column_null :bookings, :tenant_customer_id, false
    end
  end
end
