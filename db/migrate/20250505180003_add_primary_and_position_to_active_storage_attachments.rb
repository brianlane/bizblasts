class AddPrimaryAndPositionToActiveStorageAttachments < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:active_storage_attachments, :primary)
      add_column :active_storage_attachments, :primary, :boolean
    end
    
    unless column_exists?(:active_storage_attachments, :position)
      add_column :active_storage_attachments, :position, :integer
    end
  end
end
