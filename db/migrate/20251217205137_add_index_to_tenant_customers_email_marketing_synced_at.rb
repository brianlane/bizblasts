# frozen_string_literal: true

# Adds index on email_marketing_synced_at column in tenant_customers table
#
# This index improves performance for incremental email marketing sync queries
# which filter customers by email_marketing_synced_at IS NULL to find customers
# that have never been synced to email marketing platforms.
#
# See: EmailMarketing::BaseSyncService#fetch_customers_updated_since
class AddIndexToTenantCustomersEmailMarketingSyncedAt < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Using algorithm: :concurrently for zero-downtime index creation on large tables
    add_index :tenant_customers, :email_marketing_synced_at,
              algorithm: :concurrently,
              name: 'index_tenant_customers_on_email_marketing_synced_at'
  end
end
