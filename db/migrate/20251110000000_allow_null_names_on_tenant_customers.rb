class AllowNullNamesOnTenantCustomers < ActiveRecord::Migration[7.1]
  def up
    # Allow null values for first_name and last_name
    # This enables newsletter signups without requiring full name information
    change_column_null :tenant_customers, :first_name, true
    change_column_null :tenant_customers, :last_name, true
  end

  def down
    # Before reverting, set default values for any null names
    # This prevents the revert from failing due to NOT NULL constraint
    TenantCustomer.where(first_name: nil).update_all(first_name: 'Guest')
    TenantCustomer.where(last_name: nil).update_all(last_name: 'User')

    change_column_null :tenant_customers, :first_name, false
    change_column_null :tenant_customers, :last_name, false
  end
end

