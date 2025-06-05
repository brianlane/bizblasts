class RemovePhotoUrlFromStaffMembers < ActiveRecord::Migration[8.0]
  def change
    remove_column :staff_members, :photo_url, :string
  end
end
