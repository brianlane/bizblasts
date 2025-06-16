class AddEmailMarketingOptOutToTenantCustomers < ActiveRecord::Migration[8.0]
  def change
    add_column :tenant_customers, :email_marketing_opt_out, :boolean
  end
end
