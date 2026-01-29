# frozen_string_literal: true

module Calendar
  class TokenRefreshJob < ApplicationJob
    queue_as :low_priority
    
    def perform
      # Find connections that will expire within the refresh window (15 minutes)
      window = 15.minutes
      expiring_soon = CalendarConnection.active
                                       .where('token_expires_at <= ?', window.from_now)
                                       .where('refresh_token IS NOT NULL')
      
      Rails.logger.info("Found #{expiring_soon.count} calendar tokens expiring soon")
      
      expiring_soon.each do |connection|
        Rails.logger.info("Refreshing token for #{connection.staff_member.name} (#{connection.provider_display_name})")
        
        oauth_handler = OauthHandler.new
        result = oauth_handler.refresh_token(connection)
        
        if result
          Rails.logger.info("✅ Token refreshed successfully for connection #{connection.id}")
        else
          Rails.logger.error("❌ Failed to refresh token for connection #{connection.id}: #{oauth_handler.errors.full_messages.join(', ')}")
          
          # Deactivate connection if refresh fails repeatedly
          if connection.last_synced_at < 24.hours.ago
            connection.deactivate!
            Rails.logger.warn("🔒 Deactivated connection #{connection.id} due to repeated refresh failures")
          end
        end
      end
    end
  end
end