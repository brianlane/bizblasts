class CreateCalendarConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :calendar_connections do |t|
      t.references :business, null: false, foreign_key: true
      t.references :staff_member, null: false, foreign_key: true
      t.integer :provider, null: false
      t.string :uid
      t.text :access_token
      t.text :refresh_token
      t.datetime :token_expires_at
      t.text :scopes
      t.string :sync_token
      t.datetime :connected_at
      t.datetime :last_synced_at
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :calendar_connections, [:business_id, :staff_member_id, :provider], 
              name: 'index_calendar_connections_on_business_staff_provider'
    add_index :calendar_connections, :active
    add_index :calendar_connections, :last_synced_at
  end
end
