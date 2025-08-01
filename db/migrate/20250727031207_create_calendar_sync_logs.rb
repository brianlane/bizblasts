class CreateCalendarSyncLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :calendar_sync_logs do |t|
      t.references :calendar_event_mapping, null: false, foreign_key: true
      t.integer :action, null: false
      t.integer :outcome, null: false
      t.text :message
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :calendar_sync_logs, :action
    add_index :calendar_sync_logs, :outcome
    add_index :calendar_sync_logs, :created_at
    add_index :calendar_sync_logs, :metadata, using: :gin
  end
end
