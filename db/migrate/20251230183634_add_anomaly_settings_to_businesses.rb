class AddAnomalySettingsToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :anomaly_settings, :jsonb, default: {
      detection_sensitivity: 'medium',
      deviation_threshold: '20',
      monitoring_period: '30',
      email_notifications: 'critical_high'
    }
  end
end
