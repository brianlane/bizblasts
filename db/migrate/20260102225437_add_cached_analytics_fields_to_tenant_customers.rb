class AddCachedAnalyticsFieldsToTenantCustomers < ActiveRecord::Migration[8.1]
  def change
    # Add cached analytics fields for performance optimization
    add_column :tenant_customers, :cached_total_revenue, :decimal, precision: 10, scale: 2, default: 0.0, null: false
    add_column :tenant_customers, :cached_purchase_frequency, :integer, default: 0, null: false
    add_column :tenant_customers, :cached_last_purchase_at, :datetime
    add_column :tenant_customers, :cached_first_purchase_at, :datetime
    add_column :tenant_customers, :cached_days_since_last_purchase, :integer
    add_column :tenant_customers, :cached_avg_days_between_purchases, :decimal, precision: 8, scale: 2

    # Add indexes for analytics queries that filter by these values
    add_index :tenant_customers, :cached_purchase_frequency, name: 'index_tenant_customers_on_cached_purchase_freq'
    add_index :tenant_customers, :cached_total_revenue, name: 'index_tenant_customers_on_cached_total_revenue'
    add_index :tenant_customers, :cached_last_purchase_at, name: 'index_tenant_customers_on_cached_last_purchase'
    add_index :tenant_customers, :cached_days_since_last_purchase, name: 'index_tenant_customers_on_cached_days_since_purchase'
  end
end
