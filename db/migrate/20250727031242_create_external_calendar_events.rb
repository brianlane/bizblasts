class CreateExternalCalendarEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :external_calendar_events do |t|
      t.references :calendar_connection, null: false, foreign_key: true
      t.string :external_event_id, null: false
      t.string :external_calendar_id
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.text :summary
      t.datetime :last_imported_at

      t.timestamps
    end

    add_index :external_calendar_events, :external_event_id
    add_index :external_calendar_events, [:starts_at, :ends_at]
    add_index :external_calendar_events, :last_imported_at
    add_index :external_calendar_events, [:calendar_connection_id, :external_event_id], 
              name: 'index_external_calendar_events_on_connection_event_id',
              unique: true
  end
end
