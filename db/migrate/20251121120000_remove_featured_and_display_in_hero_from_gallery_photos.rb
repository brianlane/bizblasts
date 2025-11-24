class RemoveFeaturedAndDisplayInHeroFromGalleryPhotos < ActiveRecord::Migration[8.1]
  def change
    remove_index :gallery_photos, [:business_id, :featured], if_exists: true
    remove_column :gallery_photos, :featured, :boolean, default: false, null: false
    remove_column :gallery_photos, :display_in_hero, :boolean, default: false, null: false
  end
end
