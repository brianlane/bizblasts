class AddPrimaryAndPositionToActiveStorageAttachments < ActiveRecord::Migration[7.1]
  def change
    # Skip if the table doesn't exist yet (it will be created with these columns by the ActiveStorage migration)
    return unless table_exists?(:active_storage_attachments)
    
    unless column_exists?(:active_storage_attachments, :primary)
      add_column :active_storage_attachments, :primary, :boolean, default: false
    end
    
    unless column_exists?(:active_storage_attachments, :position)
      add_column :active_storage_attachments, :position, :integer, default: 0
    end
  end
end
