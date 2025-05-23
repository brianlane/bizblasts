class AddStripeCustomerIdToTenantCustomers < ActiveRecord::Migration[8.0]
  def change
    add_column :tenant_customers, :stripe_customer_id, :string
    add_index :tenant_customers, :stripe_customer_id, unique: true
  end
end 