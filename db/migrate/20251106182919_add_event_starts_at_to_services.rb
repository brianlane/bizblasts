class AddEventStartsAtToServices < ActiveRecord::Migration[8.1]
  def change
    add_column :services, :event_starts_at, :datetime
    # Add partial index for event services to optimize queries for upcoming events
    add_index :services, :event_starts_at, where: "service_type = 2", name: 'index_services_on_event_starts_at_for_events'
  end
end
