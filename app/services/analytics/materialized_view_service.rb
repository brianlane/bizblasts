# frozen_string_literal: true

module Analytics
  # Service for querying analytics materialized views
  # Provides fast access to precomputed aggregated data
  class MaterializedViewService
    attr_reader :business

    def initialize(business)
      @business = business
    end

    # Check if materialized views are available
    # @return [Boolean]
    def views_available?
      return @views_available if defined?(@views_available)

      @views_available = ActiveRecord::Base.connection.data_source_exists?('daily_analytics_summaries')
    rescue ActiveRecord::StatementInvalid
      @views_available = false
    end

    # Get aggregated daily analytics for a date range
    # @param start_date [Date]
    # @param end_date [Date]
    # @return [Array<Hash>]
    def daily_summaries(start_date, end_date)
      return [] unless views_available?

      results = execute_query(<<-SQL, [business.id, start_date, end_date])
        SELECT
          date,
          total_sessions,
          unique_visitors,
          bounced_sessions,
          conversions,
          total_conversion_value,
          avg_session_duration,
          new_visitors,
          returning_visitors
        FROM daily_analytics_summaries
        WHERE business_id = $1
          AND date >= $2
          AND date <= $3
        ORDER BY date DESC
      SQL

      results.map do |row|
        {
          date: row['date'],
          sessions: row['total_sessions'].to_i,
          visitors: row['unique_visitors'].to_i,
          bounced: row['bounced_sessions'].to_i,
          conversions: row['conversions'].to_i,
          conversion_value: row['total_conversion_value'].to_f,
          avg_duration: row['avg_session_duration'].to_f.round(0),
          new_visitors: row['new_visitors'].to_i,
          returning_visitors: row['returning_visitors'].to_i
        }
      end
    end

    # Get aggregated traffic sources for a date range
    # @param start_date [Date]
    # @param end_date [Date]
    # @return [Hash]
    def traffic_sources(start_date, end_date)
      return default_traffic_sources unless views_available?

      results = execute_query(<<-SQL, [business.id, start_date, end_date])
        SELECT
          source_type,
          SUM(session_count) as total
        FROM traffic_source_summaries
        WHERE business_id = $1
          AND date >= $2
          AND date <= $3
        GROUP BY source_type
      SQL

      sources = default_traffic_sources
      results.each do |row|
        source = row['source_type'].to_sym
        sources[source] = row['total'].to_i if sources.key?(source)
      end

      sources
    end

    # Get top pages for a date range
    # @param start_date [Date]
    # @param end_date [Date]
    # @param limit [Integer]
    # @return [Array<Hash>]
    def top_pages(start_date, end_date, limit: 5)
      return [] unless views_available?

      results = execute_query(<<-SQL, [business.id, start_date, end_date, limit])
        SELECT
          page_path,
          SUM(view_count) as total_views
        FROM top_pages_summaries
        WHERE business_id = $1
          AND date >= $2
          AND date <= $3
        GROUP BY page_path
        ORDER BY total_views DESC
        LIMIT $4
      SQL

      results.map do |row|
        {
          path: row['page_path'],
          views: row['total_views'].to_i
        }
      end
    end

    # Get period summary metrics from materialized view
    # @param start_date [Date]
    # @param end_date [Date]
    # @return [Hash]
    def period_summary(start_date, end_date)
      return nil unless views_available?

      result = execute_query(<<-SQL, [business.id, start_date, end_date]).first
        SELECT
          COALESCE(SUM(total_sessions), 0) as sessions,
          COALESCE(SUM(unique_visitors), 0) as visitors,
          COALESCE(SUM(bounced_sessions), 0) as bounced,
          COALESCE(SUM(conversions), 0) as conversions,
          COALESCE(SUM(total_conversion_value), 0) as conversion_value,
          CASE
            WHEN SUM(total_sessions) > 0
            THEN SUM(bounced_sessions)::float / SUM(total_sessions) * 100
            ELSE 0
          END as bounce_rate,
          CASE
            WHEN SUM(total_sessions) > 0
            THEN SUM(conversions)::float / SUM(total_sessions) * 100
            ELSE 0
          END as conversion_rate,
          COALESCE(AVG(avg_session_duration), 0) as avg_duration
        FROM daily_analytics_summaries
        WHERE business_id = $1
          AND date >= $2
          AND date <= $3
      SQL

      return nil unless result

      {
        sessions: result['sessions'].to_i,
        visitors: result['visitors'].to_i,
        bounced: result['bounced'].to_i,
        conversions: result['conversions'].to_i,
        conversion_value: result['conversion_value'].to_f,
        bounce_rate: result['bounce_rate'].to_f.round(1),
        conversion_rate: result['conversion_rate'].to_f.round(1),
        avg_duration: result['avg_duration'].to_f.round(0)
      }
    end

    private

    def execute_query(sql, params)
      ActiveRecord::Base.connection.exec_query(
        ActiveRecord::Base.sanitize_sql_array([sql] + params)
      ).to_a
    end

    def default_traffic_sources
      { direct: 0, organic: 0, social: 0, referral: 0, paid: 0 }
    end
  end
end
