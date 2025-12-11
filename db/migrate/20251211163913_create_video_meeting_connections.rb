# frozen_string_literal: true

class CreateVideoMeetingConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :video_meeting_connections do |t|
      t.references :business, null: false, foreign_key: true
      t.references :staff_member, null: false, foreign_key: true
      t.integer :provider, null: false, default: 0
      t.text :access_token
      t.text :refresh_token
      t.datetime :token_expires_at
      t.string :uid
      t.text :scopes
      t.boolean :active, default: true, null: false
      t.datetime :connected_at
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :video_meeting_connections, :active
    add_index :video_meeting_connections, [:business_id, :staff_member_id, :provider],
              unique: true, name: 'idx_video_meeting_connections_unique'
  end
end
