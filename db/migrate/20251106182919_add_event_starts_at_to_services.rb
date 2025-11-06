class AddEventStartsAtToServices < ActiveRecord::Migration[8.1]
  def change
    add_column :services, :event_starts_at, :datetime
  end
end
