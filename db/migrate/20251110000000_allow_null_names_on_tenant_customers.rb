class AllowNullNamesOnTenantCustomers < ActiveRecord::Migration[7.1]
  def change
    change_column_null :tenant_customers, :first_name, true
    change_column_null :tenant_customers, :last_name, true
  end
end

