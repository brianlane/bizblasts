class AddWebsitePagesAndSocialsToBusinesses < ActiveRecord::Migration[7.0]
  def change
    change_table :businesses do |t|
      t.boolean :show_services_section, default: true, null: false
      t.boolean :show_products_section, default: true, null: false
      t.boolean :show_estimate_page, default: true, null: false

      t.string :facebook_url
      t.string :twitter_url
      t.string :instagram_url
      t.string :pinterest_url
      t.string :linkedin_url
      t.string :tiktok_url
      t.string :youtube_url
    end
  end
end 