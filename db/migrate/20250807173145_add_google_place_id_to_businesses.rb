class AddGooglePlaceIdToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :google_place_id, :string
    add_index :businesses, :google_place_id, unique: true
  end
end
