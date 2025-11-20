class CreateGalleryPhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :gallery_photos do |t|
      t.references :business, null: false, foreign_key: true, index: true
      t.string :title
      t.text :description
      t.integer :position, null: false
      t.boolean :featured, default: false, null: false
      t.boolean :display_in_hero, default: false, null: false
      t.integer :photo_source, default: 0, null: false # enum: gallery, service, product
      t.string :source_type # polymorphic for Service/Product
      t.integer :source_id # polymorphic id
      t.integer :source_attachment_id # references active_storage_attachments.id

      t.timestamps
    end

    # Add composite indexes for efficient querying
    add_index :gallery_photos, [:business_id, :position], unique: true
    add_index :gallery_photos, [:business_id, :featured]
    add_index :gallery_photos, [:source_type, :source_id], where: "source_type IS NOT NULL"
  end
end
