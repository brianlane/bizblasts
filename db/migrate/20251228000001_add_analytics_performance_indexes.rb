# frozen_string_literal: true

class AddAnalyticsPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Partial index for finding open sessions (session_end IS NULL)
    # This dramatically speeds up the session aggregation job
    add_index :visitor_sessions, [:business_id, :session_start],
              where: "session_end IS NULL",
              name: "index_visitor_sessions_open_sessions"

    # Index for session aggregation job's GREATEST query
    # Helps with ordering by session_start when filtering by session_end
    add_index :visitor_sessions, :session_end,
              name: "index_visitor_sessions_on_session_end"

    # Composite index for dashboard metrics queries
    add_index :visitor_sessions, [:business_id, :converted, :created_at],
              name: "index_visitor_sessions_conversion_metrics"

    # Index for traffic source analysis
    add_index :visitor_sessions, [:business_id, :utm_source, :created_at],
              name: "index_visitor_sessions_traffic_source"

    # Index for device breakdown queries
    add_index :visitor_sessions, [:business_id, :device_type, :created_at],
              name: "index_visitor_sessions_device_metrics"

    # Page view indexes for session joins and aggregations
    add_index :page_views, [:session_id, :is_exit_page],
              name: "index_page_views_session_exit"

    # Click event indexes for conversion tracking
    add_index :click_events, [:business_id, :is_conversion, :created_at],
              name: "index_click_events_conversion_metrics"

    # Index for click category analysis
    add_index :click_events, [:session_id, :category],
              name: "index_click_events_session_category"
  end
end
