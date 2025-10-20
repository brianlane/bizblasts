class RemoveGoogleBusinessProfileIdFromBusinesses < ActiveRecord::Migration[8.0]
  def change
    remove_column :businesses, :google_business_profile_id, :string
    remove_column :businesses, :show_google_reviews, :boolean
    remove_index :businesses, name: "index_businesses_on_google_business_profile_id", if_exists: true
  end
end
