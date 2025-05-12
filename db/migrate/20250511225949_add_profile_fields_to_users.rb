class AddProfileFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :phone, :string
    add_column :users, :locale, :string
    add_column :users, :notification_preferences, :jsonb
  end
end
