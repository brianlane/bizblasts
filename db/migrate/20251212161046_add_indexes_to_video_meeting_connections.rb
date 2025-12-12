# frozen_string_literal: true

class AddIndexesToVideoMeetingConnections < ActiveRecord::Migration[8.1]
  def change
    # Composite index for common query: finding active connections for a staff member by provider
    # Used by staff_member.video_connection_for(provider) and has_video_connection?(provider)
    add_index :video_meeting_connections,
              [:staff_member_id, :provider, :active],
              name: 'idx_video_connections_staff_provider_active'

    # Index for finding all connections for a business (admin views)
    add_index :video_meeting_connections,
              [:business_id, :active],
              name: 'idx_video_connections_business_active'
  end
end
