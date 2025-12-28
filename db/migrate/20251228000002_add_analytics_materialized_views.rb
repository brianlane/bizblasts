# frozen_string_literal: true

class AddAnalyticsMaterializedViews < ActiveRecord::Migration[8.0]
  def up
    # Materialized view for daily analytics summary
    # This view precomputes daily aggregated metrics for fast dashboard queries
    execute <<-SQL
      CREATE MATERIALIZED VIEW IF NOT EXISTS daily_analytics_summaries AS
      SELECT
        business_id,
        DATE(session_start) as date,
        COUNT(*) as total_sessions,
        COUNT(DISTINCT visitor_fingerprint) as unique_visitors,
        COUNT(*) FILTER (WHERE is_bounce = true) as bounced_sessions,
        COUNT(*) FILTER (WHERE converted = true) as conversions,
        COALESCE(SUM(conversion_value) FILTER (WHERE converted = true), 0) as total_conversion_value,
        COALESCE(AVG(duration_seconds), 0) as avg_session_duration,
        COUNT(*) FILTER (WHERE is_returning_visitor = false) as new_visitors,
        COUNT(*) FILTER (WHERE is_returning_visitor = true) as returning_visitors
      FROM visitor_sessions
      WHERE session_start IS NOT NULL
      GROUP BY business_id, DATE(session_start)
      WITH DATA;
    SQL

    # Add unique index for concurrent refresh and fast lookups
    execute <<-SQL
      CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_analytics_summaries_unique
      ON daily_analytics_summaries (business_id, date);
    SQL

    # Additional index for date range queries
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS idx_daily_analytics_summaries_date
      ON daily_analytics_summaries (date DESC);
    SQL

    # Materialized view for traffic source breakdown
    execute <<-SQL
      CREATE MATERIALIZED VIEW IF NOT EXISTS traffic_source_summaries AS
      SELECT
        business_id,
        DATE(session_start) as date,
        CASE
          WHEN LOWER(utm_medium) IN ('cpc', 'ppc', 'paid') THEN 'paid'
          WHEN first_referrer_domain IS NULL OR first_referrer_domain = '' THEN 'direct'
          WHEN LOWER(first_referrer_domain) LIKE '%google%'
            OR LOWER(first_referrer_domain) LIKE '%bing%'
            OR LOWER(first_referrer_domain) LIKE '%yahoo%'
            OR LOWER(first_referrer_domain) LIKE '%duckduckgo%' THEN 'organic'
          WHEN LOWER(first_referrer_domain) LIKE '%facebook%'
            OR LOWER(first_referrer_domain) LIKE '%twitter%'
            OR LOWER(first_referrer_domain) LIKE '%instagram%'
            OR LOWER(first_referrer_domain) LIKE '%linkedin%'
            OR LOWER(first_referrer_domain) LIKE '%pinterest%'
            OR LOWER(first_referrer_domain) LIKE '%tiktok%' THEN 'social'
          ELSE 'referral'
        END as source_type,
        COUNT(*) as session_count
      FROM visitor_sessions
      WHERE session_start IS NOT NULL
      GROUP BY business_id, DATE(session_start),
        CASE
          WHEN LOWER(utm_medium) IN ('cpc', 'ppc', 'paid') THEN 'paid'
          WHEN first_referrer_domain IS NULL OR first_referrer_domain = '' THEN 'direct'
          WHEN LOWER(first_referrer_domain) LIKE '%google%'
            OR LOWER(first_referrer_domain) LIKE '%bing%'
            OR LOWER(first_referrer_domain) LIKE '%yahoo%'
            OR LOWER(first_referrer_domain) LIKE '%duckduckgo%' THEN 'organic'
          WHEN LOWER(first_referrer_domain) LIKE '%facebook%'
            OR LOWER(first_referrer_domain) LIKE '%twitter%'
            OR LOWER(first_referrer_domain) LIKE '%instagram%'
            OR LOWER(first_referrer_domain) LIKE '%linkedin%'
            OR LOWER(first_referrer_domain) LIKE '%pinterest%'
            OR LOWER(first_referrer_domain) LIKE '%tiktok%' THEN 'social'
          ELSE 'referral'
        END
      WITH DATA;
    SQL

    # Add unique index for concurrent refresh
    execute <<-SQL
      CREATE UNIQUE INDEX IF NOT EXISTS idx_traffic_source_summaries_unique
      ON traffic_source_summaries (business_id, date, source_type);
    SQL

    # Materialized view for top pages by business and date
    execute <<-SQL
      CREATE MATERIALIZED VIEW IF NOT EXISTS top_pages_summaries AS
      SELECT
        business_id,
        DATE(created_at) as date,
        page_path,
        COUNT(*) as view_count
      FROM page_views
      WHERE created_at IS NOT NULL
      GROUP BY business_id, DATE(created_at), page_path
      WITH DATA;
    SQL

    # Add unique index for concurrent refresh
    execute <<-SQL
      CREATE UNIQUE INDEX IF NOT EXISTS idx_top_pages_summaries_unique
      ON top_pages_summaries (business_id, date, page_path);
    SQL

    # Index for efficient date range queries
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS idx_top_pages_summaries_date
      ON top_pages_summaries (business_id, date DESC, view_count DESC);
    SQL
  end

  def down
    execute "DROP MATERIALIZED VIEW IF EXISTS top_pages_summaries CASCADE;"
    execute "DROP MATERIALIZED VIEW IF EXISTS traffic_source_summaries CASCADE;"
    execute "DROP MATERIALIZED VIEW IF EXISTS daily_analytics_summaries CASCADE;"
  end
end
