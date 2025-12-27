# frozen_string_literal: true

class CreateAnalyticsSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :analytics_snapshots do |t|
      t.references :business, null: false, foreign_key: true, index: true
      
      # Snapshot type and period
      t.string :snapshot_type, null: false # daily, weekly, monthly
      t.date :period_start, null: false
      t.date :period_end, null: false
      
      # Traffic metrics
      t.integer :unique_visitors, default: 0
      t.integer :total_page_views, default: 0
      t.integer :total_sessions, default: 0
      t.decimal :bounce_rate, precision: 5, scale: 2, default: 0
      t.integer :avg_session_duration, default: 0 # seconds
      t.decimal :pages_per_session, precision: 5, scale: 2, default: 0
      
      # Engagement metrics
      t.integer :total_clicks, default: 0
      t.integer :unique_pages_viewed, default: 0
      
      # Conversion metrics
      t.integer :total_conversions, default: 0
      t.decimal :conversion_rate, precision: 5, scale: 2, default: 0
      t.decimal :total_conversion_value, precision: 12, scale: 2, default: 0
      
      # Revenue component metrics (JSONB for flexibility)
      t.jsonb :booking_metrics, default: {}
      # { total: 0, completed: 0, cancelled: 0, revenue: 0, avg_value: 0, by_service: {} }
      
      t.jsonb :product_metrics, default: {}
      # { views: 0, purchases: 0, revenue: 0, top_products: [], conversion_rate: 0 }
      
      t.jsonb :service_metrics, default: {}
      # { views: 0, bookings: 0, top_services: [], conversion_rate: 0 }
      
      t.jsonb :estimate_metrics, default: {}
      # { sent: 0, viewed: 0, approved: 0, total_value: 0, conversion_rate: 0 }
      
      # Traffic source breakdown
      t.jsonb :traffic_sources, default: {}
      # { direct: 0, organic: 0, referral: 0, social: 0, paid: 0 }
      
      t.jsonb :top_referrers, default: []
      # [{ domain: 'google.com', visits: 100 }, ...]
      
      t.jsonb :top_pages, default: []
      # [{ path: '/services', views: 100, avg_time: 45 }, ...]
      
      # Device breakdown
      t.jsonb :device_breakdown, default: {}
      # { desktop: 60, mobile: 35, tablet: 5 }
      
      # Geographic breakdown
      t.jsonb :geo_breakdown, default: {}
      # { US: 80, CA: 10, UK: 5, other: 5 }
      
      # UTM campaign performance
      t.jsonb :campaign_metrics, default: {}
      # { campaign_name: { visits: 0, conversions: 0, revenue: 0 } }
      
      t.datetime :generated_at, null: false

      t.timestamps
    end

    # Performance indexes
    add_index :analytics_snapshots, [:business_id, :snapshot_type, :period_start], 
              name: 'idx_analytics_snapshots_business_type_period'
    add_index :analytics_snapshots, [:business_id, :period_start, :period_end]
    add_index :analytics_snapshots, :snapshot_type
    
    # Ensure uniqueness for a business/type/period combination
    add_index :analytics_snapshots, [:business_id, :snapshot_type, :period_start, :period_end], 
              unique: true, name: 'idx_analytics_snapshots_unique_period'
  end
end

