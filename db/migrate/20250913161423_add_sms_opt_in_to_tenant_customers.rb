class AddSmsOptInToTenantCustomers < ActiveRecord::Migration[8.0]
  def change
    add_column :tenant_customers, :phone_opt_in, :boolean, default: false, null: false
    add_column :tenant_customers, :phone_opt_in_at, :datetime
    add_column :tenant_customers, :phone_marketing_opt_out, :boolean, default: false, null: false
  end
end
