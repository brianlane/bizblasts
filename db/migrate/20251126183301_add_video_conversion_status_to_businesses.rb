class AddVideoConversionStatusToBusinesses < ActiveRecord::Migration[8.1]
  def change
    # Track video conversion status: nil (no conversion needed), 'pending', 'converting', 'completed', 'failed'
    add_column :businesses, :video_conversion_status, :string, default: nil
  end
end
