class AddGalleryVideoToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :video_display_location, :integer, default: 0, null: false # enum: hero, gallery, both
    add_column :businesses, :video_title, :string
    add_column :businesses, :video_autoplay_hero, :boolean, default: true, null: false

    # Add index for video display location queries
    add_index :businesses, :video_display_location
  end
end
