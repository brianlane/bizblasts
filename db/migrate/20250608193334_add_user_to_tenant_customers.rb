class AddUserToTenantCustomers < ActiveRecord::Migration[8.0]
  def change
    add_reference :tenant_customers, :user, foreign_key: true, null: true
  end
end
