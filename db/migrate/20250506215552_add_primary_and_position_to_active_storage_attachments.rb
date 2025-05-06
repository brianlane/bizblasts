class AddPrimaryAndPositionToActiveStorageAttachments < ActiveRecord::Migration[8.0]
  def change
    # Skip if the table doesn't exist yet (it will be created with these columns by the ActiveStorage migration)
    return unless table_exists?(:active_storage_attachments)
    
    unless column_exists?(:active_storage_attachments, :primary)
      add_column :active_storage_attachments, :primary, :boolean
    end
    
    unless column_exists?(:active_storage_attachments, :position)
      add_column :active_storage_attachments, :position, :integer
    end
  end
end
