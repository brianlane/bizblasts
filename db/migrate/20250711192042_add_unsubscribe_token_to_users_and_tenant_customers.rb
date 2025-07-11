class AddUnsubscribeTokenToUsersAndTenantCustomers < ActiveRecord::Migration[8.0]
  def change
    # Add unsubscribe fields to users table
    add_column :users, :unsubscribe_token, :string
    add_column :users, :unsubscribed_at, :datetime
    add_index :users, :unsubscribe_token, unique: true
    
    # Add unsubscribe fields to tenant_customers table
    add_column :tenant_customers, :unsubscribe_token, :string
    add_column :tenant_customers, :unsubscribed_at, :datetime
    add_index :tenant_customers, :unsubscribe_token, unique: true
  end
end
