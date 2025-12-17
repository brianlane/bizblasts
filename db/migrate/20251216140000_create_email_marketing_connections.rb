# frozen_string_literal: true

class CreateEmailMarketingConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :email_marketing_connections do |t|
      t.references :business, null: false, foreign_key: true
      t.integer :provider, null: false, default: 0
      t.text :access_token
      t.text :refresh_token
      t.datetime :token_expires_at
      t.string :account_id
      t.string :account_email
      t.string :api_server # Mailchimp datacenter (e.g., us1, us2)
      t.string :default_list_id
      t.string :default_list_name
      t.jsonb :config, default: {}
      t.jsonb :field_mappings, default: {}
      t.integer :sync_strategy, default: 0, null: false
      t.boolean :sync_on_customer_create, default: true
      t.boolean :sync_on_customer_update, default: true
      t.boolean :receive_unsubscribe_webhooks, default: true
      t.boolean :active, default: true
      t.datetime :connected_at
      t.datetime :last_synced_at
      t.integer :total_contacts_synced, default: 0

      t.timestamps
    end

    add_index :email_marketing_connections, [:business_id, :provider], unique: true, name: 'idx_email_marketing_conn_business_provider'
    add_index :email_marketing_connections, :provider
    add_index :email_marketing_connections, :active
  end
end
