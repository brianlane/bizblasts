class AddUniquePhoneIndexForLinkedUsers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  
  def up
    # Add unique constraint on [:business_id, :phone] for linked users (user_id IS NOT NULL)
    # This ensures one phone number per business for actual user accounts
    # Guests (user_id IS NULL) can share phone numbers with users
    unless index_exists?(:tenant_customers, [:business_id, :phone], 
                         name: :index_tenant_customers_on_business_phone_for_users,
                         where: "user_id IS NOT NULL")
      add_index :tenant_customers, [:business_id, :phone],
                unique: true,
                where: "user_id IS NOT NULL",
                algorithm: :concurrently,
                name: :index_tenant_customers_on_business_phone_for_users
    end
  end
  
  def down
    if index_exists?(:tenant_customers, [:business_id, :phone], 
                     name: :index_tenant_customers_on_business_phone_for_users)
      remove_index :tenant_customers, 
                   name: :index_tenant_customers_on_business_phone_for_users,
                   algorithm: :concurrently
    end
  end
end
