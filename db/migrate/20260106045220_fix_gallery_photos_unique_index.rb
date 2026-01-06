class FixGalleryPhotosUniqueIndex < ActiveRecord::Migration[8.1]
  def up
    # Remove the old unique index on [business_id, position]
    remove_index :gallery_photos, name: "index_gallery_photos_on_business_id_and_position"

    # Add new unique index on [owner_type, owner_id, position]
    # This allows different owners (businesses or sections) to have independent position sequences
    add_index :gallery_photos, [:owner_type, :owner_id, :position],
              unique: true,
              name: "index_gallery_photos_on_owner_and_position"
  end

  def down
    # Reverse the changes
    remove_index :gallery_photos, name: "index_gallery_photos_on_owner_and_position"
    add_index :gallery_photos, [:business_id, :position],
              unique: true,
              name: "index_gallery_photos_on_business_id_and_position"
  end
end
