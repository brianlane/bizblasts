# frozen_string_literal: true

class AddAnalyticsSidebarItemToExistingUsers < ActiveRecord::Migration[8.0]
  def up
    # Find all users who have customized their sidebar (have any user_sidebar_items)
    user_ids_with_sidebar = UserSidebarItem.distinct.pluck(:user_id)

    user_ids_with_sidebar.each do |user_id|
      # Skip if user already has analytics item
      next if UserSidebarItem.exists?(user_id: user_id, item_key: 'analytics')

      # Find position of 'dashboard' item to insert after it
      dashboard_item = UserSidebarItem.find_by(user_id: user_id, item_key: 'dashboard')

      if dashboard_item
        dashboard_position = dashboard_item.position

        # Shift all items after dashboard down by 1 to make room for analytics
        UserSidebarItem.where(user_id: user_id)
                       .where('position > ?', dashboard_position)
                       .update_all('position = position + 1')

        # Add analytics right after dashboard
        UserSidebarItem.create!(
          user_id: user_id,
          item_key: 'analytics',
          position: dashboard_position + 1,
          visible: true
        )
      else
        # No dashboard item found, add analytics at position 1 (second position)
        # First shift everything down
        UserSidebarItem.where(user_id: user_id)
                       .where('position >= ?', 1)
                       .update_all('position = position + 1')

        UserSidebarItem.create!(
          user_id: user_id,
          item_key: 'analytics',
          position: 1,
          visible: true
        )
      end
    end
  end

  def down
    # Remove the analytics items
    UserSidebarItem.where(item_key: 'analytics').destroy_all
  end
end

