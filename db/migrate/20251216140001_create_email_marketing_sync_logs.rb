# frozen_string_literal: true

class CreateEmailMarketingSyncLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :email_marketing_sync_logs do |t|
      t.references :email_marketing_connection, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: true
      t.integer :sync_type, default: 0, null: false
      t.integer :status, default: 0, null: false
      t.integer :direction, default: 0, null: false # outbound (to platform) or inbound (from platform)
      t.integer :contacts_synced, default: 0
      t.integer :contacts_created, default: 0
      t.integer :contacts_updated, default: 0
      t.integer :contacts_failed, default: 0
      t.jsonb :error_details, default: []
      t.jsonb :summary, default: {}
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :email_marketing_sync_logs, :sync_type
    add_index :email_marketing_sync_logs, :status
    add_index :email_marketing_sync_logs, :created_at
  end
end
