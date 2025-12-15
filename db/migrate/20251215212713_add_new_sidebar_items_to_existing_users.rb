# frozen_string_literal: true

class AddNewSidebarItemsToExistingUsers < ActiveRecord::Migration[8.0]
  def up
    # Find all users who have customized their sidebar (have any user_sidebar_items)
    user_ids_with_sidebar = UserSidebarItem.distinct.pluck(:user_id)

    user_ids_with_sidebar.each do |user_id|
      # Get the current max position for this user
      max_position = UserSidebarItem.where(user_id: user_id).maximum(:position) || 0

      # Find position of 'settings' item to insert before it
      settings_item = UserSidebarItem.find_by(user_id: user_id, item_key: 'settings')

      if settings_item
        settings_position = settings_item.position

        # Shift settings (and anything after) down by 2 to make room
        UserSidebarItem.where(user_id: user_id)
                       .where('position >= ?', settings_position)
                       .update_all('position = position + 2')

        # Add document_templates at settings' old position
        unless UserSidebarItem.exists?(user_id: user_id, item_key: 'document_templates')
          UserSidebarItem.create!(
            user_id: user_id,
            item_key: 'document_templates',
            position: settings_position,
            visible: true
          )
        end

        # Add csv_import_export right after document_templates
        unless UserSidebarItem.exists?(user_id: user_id, item_key: 'csv_import_export')
          UserSidebarItem.create!(
            user_id: user_id,
            item_key: 'csv_import_export',
            position: settings_position + 1,
            visible: true
          )
        end
      else
        # No settings item found, just add at the end
        unless UserSidebarItem.exists?(user_id: user_id, item_key: 'document_templates')
          UserSidebarItem.create!(
            user_id: user_id,
            item_key: 'document_templates',
            position: max_position + 1,
            visible: true
          )
        end

        unless UserSidebarItem.exists?(user_id: user_id, item_key: 'csv_import_export')
          UserSidebarItem.create!(
            user_id: user_id,
            item_key: 'csv_import_export',
            position: max_position + 2,
            visible: true
          )
        end
      end

      # Also remove any invalid 'platform' items that may exist
      UserSidebarItem.where(user_id: user_id, item_key: 'platform').destroy_all
    end
  end

  def down
    # Remove the added items
    UserSidebarItem.where(item_key: %w[document_templates csv_import_export]).destroy_all
  end
end
