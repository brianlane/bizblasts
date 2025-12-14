# frozen_string_literal: true

class CreateQuickbooksConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :quickbooks_connections do |t|
      t.references :business, null: false, foreign_key: true, index: { unique: true }

      # Intuit company identifier
      t.string :realm_id, null: false

      # OAuth tokens (encrypted at rest in model)
      t.text :access_token
      t.text :refresh_token
      t.datetime :token_expires_at
      t.datetime :refresh_token_expires_at

      # Metadata
      t.text :scopes
      t.string :environment, null: false, default: 'production'
      t.boolean :active, null: false, default: true
      t.datetime :connected_at
      t.datetime :last_used_at
      t.datetime :last_synced_at

      # Provider-specific settings / mappings
      t.jsonb :config, null: false, default: {}

      t.timestamps
    end

    add_index :quickbooks_connections, :active
    add_index :quickbooks_connections, :realm_id
  end
end
