class RemoveLegacyPhoneCiphertextColumns < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  
  def up
    # Remove legacy phone_ciphertext from tenant_customers
    if index_exists?(:tenant_customers, [:business_id, :phone_ciphertext], name: :idx_tenant_cust_on_biz_and_phone_users_only)
      remove_index :tenant_customers, name: :idx_tenant_cust_on_biz_and_phone_users_only, algorithm: :concurrently
    end
    
    if column_exists?(:tenant_customers, :phone_ciphertext)
      remove_column :tenant_customers, :phone_ciphertext
    end
    
    # Remove legacy phone_ciphertext from users
    if index_exists?(:users, :phone_ciphertext)
      remove_index :users, :phone_ciphertext, algorithm: :concurrently
    end
    
    if column_exists?(:users, :phone_ciphertext)
      remove_column :users, :phone_ciphertext
    end
  end
  
  def down
    # Re-add columns for rollback (though data would be lost)
    add_column :tenant_customers, :phone_ciphertext, :text unless column_exists?(:tenant_customers, :phone_ciphertext)
    add_column :users, :phone_ciphertext, :text unless column_exists?(:users, :phone_ciphertext)
    
    # Re-add indexes
    unless index_exists?(:tenant_customers, [:business_id, :phone_ciphertext], name: :idx_tenant_cust_on_biz_and_phone_users_only)
      add_index :tenant_customers, [:business_id, :phone_ciphertext],
                unique: true,
                where: "user_id IS NOT NULL",
                algorithm: :concurrently,
                name: :idx_tenant_cust_on_biz_and_phone_users_only
    end
    
    unless index_exists?(:users, :phone_ciphertext)
      add_index :users, :phone_ciphertext, algorithm: :concurrently
    end
  end
end
