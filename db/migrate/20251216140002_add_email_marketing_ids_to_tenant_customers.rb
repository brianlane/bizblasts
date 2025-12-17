# frozen_string_literal: true

class AddEmailMarketingIdsToTenantCustomers < ActiveRecord::Migration[8.1]
  def change
    add_column :tenant_customers, :mailchimp_subscriber_hash, :string
    add_column :tenant_customers, :mailchimp_list_id, :string
    add_column :tenant_customers, :constant_contact_id, :string
    add_column :tenant_customers, :email_marketing_synced_at, :datetime

    add_index :tenant_customers, :mailchimp_subscriber_hash
    add_index :tenant_customers, :constant_contact_id
  end
end
