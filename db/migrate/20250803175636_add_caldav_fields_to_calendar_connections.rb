class AddCaldavFieldsToCalendarConnections < ActiveRecord::Migration[8.0]
  def change
    add_column :calendar_connections, :caldav_username, :string
    add_column :calendar_connections, :caldav_password, :text
    add_column :calendar_connections, :caldav_url, :string
    add_column :calendar_connections, :caldav_provider, :string
  end
end
