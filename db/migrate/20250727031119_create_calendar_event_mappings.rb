class CreateCalendarEventMappings < ActiveRecord::Migration[8.0]
  def change
    create_table :calendar_event_mappings do |t|
      t.references :booking, null: false, foreign_key: true
      t.references :calendar_connection, null: false, foreign_key: true
      t.string :external_event_id, null: false
      t.string :external_calendar_id
      t.integer :status, default: 0, null: false
      t.datetime :last_synced_at
      t.text :last_error

      t.timestamps
    end

    add_index :calendar_event_mappings, :external_event_id
    add_index :calendar_event_mappings, [:booking_id, :calendar_connection_id], 
              name: 'index_calendar_event_mappings_on_booking_connection'
    add_index :calendar_event_mappings, :status
  end
end
