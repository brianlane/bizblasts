class AddGoogleBusinessProfileIdToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :google_business_profile_id, :string
    add_column :businesses, :show_google_reviews, :boolean, default: true, null: false

    add_index :businesses, :google_business_profile_id
  end
end
