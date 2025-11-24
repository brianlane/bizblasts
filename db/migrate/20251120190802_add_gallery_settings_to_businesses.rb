class AddGallerySettingsToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :gallery_enabled, :boolean, default: false, null: false
    add_column :businesses, :gallery_layout, :integer, default: 0, null: false # enum: grid (future: masonry, carousel)
    add_column :businesses, :gallery_columns, :integer, default: 3, null: false # 2-4 columns
    add_column :businesses, :show_gallery_section, :boolean, default: true, null: false

    # Add index for gallery enabled businesses
    add_index :businesses, :gallery_enabled
  end
end
