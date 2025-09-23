class AddUniqueIndexToTenantCustomersEmailAndBusiness < ActiveRecord::Migration[8.0]
  def up
    # Remove existing non-unique index if it exists
    remove_index :tenant_customers, :email, if_exists: true
    
    # Double-check for any remaining duplicates before creating unique index
    duplicates_sql = <<~SQL
      SELECT business_id, LOWER(email) as normalized_email, COUNT(*) as count
      FROM tenant_customers 
      GROUP BY business_id, LOWER(email)
      HAVING COUNT(*) > 1
    SQL
    
    duplicates = execute(duplicates_sql).to_a
    
    if duplicates.any?
      say "ERROR: Still found #{duplicates.length} duplicate group(s) after cleanup:"
      duplicates.each do |dup|
        say "  Business #{dup['business_id']}: #{dup['normalized_email']} (#{dup['count']} records)"
      end
      raise StandardError, "Cannot create unique index - duplicates still exist. Manual intervention required."
    end
    
    # Add unique composite index on business_id and email (case-insensitive)
    add_index :tenant_customers, 
              "business_id, LOWER(email)", 
              unique: true, 
              name: "index_tenant_customers_on_business_id_and_lower_email"
    
    say "Successfully created unique index on tenant_customers (business_id, LOWER(email))"
  end
  
  def down
    remove_index :tenant_customers, 
                 name: "index_tenant_customers_on_business_id_and_lower_email"
    
    # Restore the original non-unique email index
    add_index :tenant_customers, :email, if_exists: false
  end
end
