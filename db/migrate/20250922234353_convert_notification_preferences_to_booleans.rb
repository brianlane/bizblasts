class ConvertNotificationPreferencesToBooleans < ActiveRecord::Migration[8.0]
  def up
    # Convert string "0"/"1" values to proper booleans in notification_preferences
    User.where.not(notification_preferences: nil).find_each do |user|
      updated_preferences = {}
      
      user.notification_preferences.each do |key, value|
        case value
        when "1", 1, true
          updated_preferences[key] = true
        when "0", 0, false
          updated_preferences[key] = false
        else
          # Keep non-boolean values as-is (shouldn't happen, but safety)
          updated_preferences[key] = value
        end
      end
      
      # Only update if there were changes
      if updated_preferences != user.notification_preferences
        user.update_column(:notification_preferences, updated_preferences)
        Rails.logger.info "[MIGRATION] Updated notification preferences for User ##{user.id}"
      end
    end
    
    Rails.logger.info "[MIGRATION] Completed notification preferences conversion to booleans"
  end
  
  def down
    # Convert boolean values back to strings for rollback
    User.where.not(notification_preferences: nil).find_each do |user|
      updated_preferences = {}
      
      user.notification_preferences.each do |key, value|
        case value
        when true
          updated_preferences[key] = "1"
        when false
          updated_preferences[key] = "0"
        else
          # Keep non-boolean values as-is
          updated_preferences[key] = value
        end
      end
      
      # Only update if there were changes
      if updated_preferences != user.notification_preferences
        user.update_column(:notification_preferences, updated_preferences)
        Rails.logger.info "[MIGRATION ROLLBACK] Reverted notification preferences for User ##{user.id}"
      end
    end
    
    Rails.logger.info "[MIGRATION ROLLBACK] Reverted notification preferences back to strings"
  end
end
