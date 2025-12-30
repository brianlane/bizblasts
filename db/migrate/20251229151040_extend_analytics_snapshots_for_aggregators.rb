class ExtendAnalyticsSnapshotsForAggregators < ActiveRecord::Migration[8.1]
  def change
    # Add JSONB columns for new aggregated metrics categories
    add_column :analytics_snapshots, :customer_metrics, :jsonb, default: {}
    add_column :analytics_snapshots, :staff_metrics, :jsonb, default: {}
    add_column :analytics_snapshots, :inventory_metrics, :jsonb, default: {}
    add_column :analytics_snapshots, :operational_metrics, :jsonb, default: {}
    add_column :analytics_snapshots, :marketing_metrics, :jsonb, default: {}
    add_column :analytics_snapshots, :subscription_metrics, :jsonb, default: {}
    add_column :analytics_snapshots, :predictions, :jsonb, default: {}

    # Add GIN indexes for efficient JSONB querying
    add_index :analytics_snapshots, :customer_metrics, using: :gin
    add_index :analytics_snapshots, :staff_metrics, using: :gin
    add_index :analytics_snapshots, :inventory_metrics, using: :gin
    add_index :analytics_snapshots, :operational_metrics, using: :gin
    add_index :analytics_snapshots, :marketing_metrics, using: :gin
    add_index :analytics_snapshots, :subscription_metrics, using: :gin
    add_index :analytics_snapshots, :predictions, using: :gin
  end
end
