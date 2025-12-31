class AddRevenueMetricsToAnalyticsSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :analytics_snapshots, :revenue_metrics, :jsonb, default: {}
    add_index :analytics_snapshots, :revenue_metrics, using: :gin
  end
end
