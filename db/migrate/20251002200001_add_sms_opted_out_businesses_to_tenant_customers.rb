class AddSmsOptedOutBusinessesToTenantCustomers < ActiveRecord::Migration[8.0]
  def change
    add_column :tenant_customers, :sms_opted_out_businesses, :jsonb, default: []

    # Add GIN index for efficient JSONB queries
    add_index :tenant_customers, :sms_opted_out_businesses, using: :gin
  end
end