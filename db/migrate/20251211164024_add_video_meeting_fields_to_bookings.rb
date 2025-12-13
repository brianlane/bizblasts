# frozen_string_literal: true

class AddVideoMeetingFieldsToBookings < ActiveRecord::Migration[8.1]
  def change
    add_column :bookings, :video_meeting_url, :string
    add_column :bookings, :video_meeting_host_url, :string
    add_column :bookings, :video_meeting_id, :string
    add_column :bookings, :video_meeting_provider, :integer, default: 0, null: false
    add_column :bookings, :video_meeting_password, :string
    add_column :bookings, :video_meeting_status, :integer, default: 0, null: false

    add_index :bookings, :video_meeting_id
    add_index :bookings, :video_meeting_status
  end
end
