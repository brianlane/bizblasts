class AddPrimaryAndPositionToActiveStorageAttachments < ActiveRecord::Migration[8.0]
  def change
    add_column :active_storage_attachments, :primary, :boolean
    add_column :active_storage_attachments, :position, :integer
  end
end
