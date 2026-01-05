class AddPolymorphicOwnerToGalleryPhotos < ActiveRecord::Migration[8.1]
  def change
    add_column :gallery_photos, :owner_type, :string
    add_column :gallery_photos, :owner_id, :bigint
    add_index :gallery_photos, [:owner_type, :owner_id]

    # Make business_id optional for section-owned photos
    change_column_null :gallery_photos, :business_id, true

    # Backfill existing photos to be business-owned
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE gallery_photos
          SET owner_type = 'Business', owner_id = business_id
          WHERE owner_type IS NULL
        SQL
      end
    end
  end
end
