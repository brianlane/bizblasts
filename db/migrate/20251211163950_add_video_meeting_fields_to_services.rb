# frozen_string_literal: true

class AddVideoMeetingFieldsToServices < ActiveRecord::Migration[8.1]
  def change
    add_column :services, :video_enabled, :boolean, default: false, null: false
    add_column :services, :video_provider, :integer, default: 0, null: false

    add_index :services, :video_enabled
  end
end
