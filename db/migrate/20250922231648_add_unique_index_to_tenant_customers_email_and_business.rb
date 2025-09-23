class AddUniqueIndexToTenantCustomersEmailAndBusiness < ActiveRecord::Migration[8.0]
  def change
    # Remove existing non-unique index if it exists
    remove_index :tenant_customers, :email, if_exists: true
    
    # Add unique composite index on business_id and email (case-insensitive)
    add_index :tenant_customers, 
              "business_id, LOWER(email)", 
              unique: true, 
              name: "index_tenant_customers_on_business_id_and_lower_email"
  end
end
