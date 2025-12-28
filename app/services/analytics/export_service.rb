# frozen_string_literal: true

module Analytics
  # Service for exporting analytics data in various formats
  class ExportService
    include Analytics::QueryMonitoring

    attr_reader :business

    EXPORT_FORMATS = %w[csv json].freeze
    MAX_RECORDS = 50_000 # Limit to prevent memory issues

    def initialize(business)
      @business = business
    end

    # Export analytics data
    # @param type [Symbol] :sessions, :page_views, :clicks, :conversions, :summary
    # @param start_date [Date] Start of date range
    # @param end_date [Date] End of date range
    # @param format [String] 'csv' or 'json'
    # @return [Hash] { data: String, filename: String, content_type: String }
    def export(type:, start_date:, end_date:, format: 'csv')
      raise ArgumentError, "Invalid format: #{format}" unless EXPORT_FORMATS.include?(format)
      raise ArgumentError, "Invalid export type: #{type}" unless respond_to?("export_#{type}", true)

      timed_query("export_#{type}") do
        data = send("export_#{type}", start_date, end_date)

        case format
        when 'csv'
          generate_csv(data, type)
        when 'json'
          generate_json(data, type)
        end
      end
    end

    # Get available export types
    def self.available_export_types
      %w[sessions page_views clicks conversions summary]
    end

    private

    def export_sessions(start_date, end_date)
      business.visitor_sessions
        .where(session_start: start_date.beginning_of_day..end_date.end_of_day)
        .order(session_start: :desc)
        .limit(MAX_RECORDS)
        .map do |session|
          {
            session_id: session.session_id,
            visitor_fingerprint: session.visitor_fingerprint,
            session_start: session.session_start&.iso8601,
            session_end: session.session_end&.iso8601,
            duration_seconds: session.duration_seconds,
            page_view_count: session.page_view_count,
            click_count: session.click_count,
            is_bounce: session.is_bounce,
            entry_page: session.entry_page,
            exit_page: session.exit_page,
            device_type: session.device_type,
            browser: session.browser,
            os: session.os,
            country: session.country,
            utm_source: session.utm_source,
            utm_medium: session.utm_medium,
            utm_campaign: session.utm_campaign,
            converted: session.converted,
            conversion_type: session.conversion_type,
            conversion_value: session.conversion_value&.to_f,
            is_returning_visitor: session.is_returning_visitor
          }
        end
    end

    def export_page_views(start_date, end_date)
      business.page_views
        .where(created_at: start_date.beginning_of_day..end_date.end_of_day)
        .order(created_at: :desc)
        .limit(MAX_RECORDS)
        .map do |pv|
          {
            timestamp: pv.created_at&.iso8601,
            session_id: pv.session_id,
            page_path: pv.page_path,
            page_type: pv.page_type,
            page_title: pv.page_title,
            referrer_domain: pv.referrer_domain,
            utm_source: pv.utm_source,
            utm_medium: pv.utm_medium,
            utm_campaign: pv.utm_campaign,
            device_type: pv.device_type,
            browser: pv.browser,
            os: pv.os,
            country: pv.country,
            time_on_page: pv.time_on_page,
            scroll_depth: pv.scroll_depth,
            is_entry_page: pv.is_entry_page,
            is_exit_page: pv.is_exit_page,
            is_bounce: pv.is_bounce
          }
        end
    end

    def export_clicks(start_date, end_date)
      business.click_events
        .where(created_at: start_date.beginning_of_day..end_date.end_of_day)
        .order(created_at: :desc)
        .limit(MAX_RECORDS)
        .map do |click|
          {
            timestamp: click.created_at&.iso8601,
            session_id: click.session_id,
            page_path: click.page_path,
            element_type: click.element_type,
            element_text: click.element_text,
            element_identifier: click.element_identifier,
            category: click.category,
            action: click.action,
            label: click.label,
            is_conversion: click.is_conversion,
            conversion_type: click.conversion_type,
            conversion_value: click.conversion_value&.to_f
          }
        end
    end

    def export_conversions(start_date, end_date)
      business.visitor_sessions
        .converted
        .where(conversion_time: start_date.beginning_of_day..end_date.end_of_day)
        .order(conversion_time: :desc)
        .limit(MAX_RECORDS)
        .map do |session|
          {
            conversion_time: session.conversion_time&.iso8601,
            session_id: session.session_id,
            conversion_type: session.conversion_type,
            conversion_value: session.conversion_value&.to_f,
            entry_page: session.entry_page,
            utm_source: session.utm_source,
            utm_medium: session.utm_medium,
            utm_campaign: session.utm_campaign,
            device_type: session.device_type,
            is_returning_visitor: session.is_returning_visitor,
            page_view_count: session.page_view_count
          }
        end
    end

    def export_summary(start_date, end_date)
      # Generate daily summary for the date range
      (start_date..end_date).map do |date|
        date_range = date.beginning_of_day..date.end_of_day

        sessions = business.visitor_sessions.where(session_start: date_range)
        page_views = business.page_views.where(created_at: date_range)
        clicks = business.click_events.where(created_at: date_range)

        total_sessions = sessions.count
        bounced = sessions.bounced.count
        converted = sessions.converted.count

        {
          date: date.iso8601,
          unique_visitors: sessions.distinct.count(:visitor_fingerprint),
          total_sessions: total_sessions,
          total_page_views: page_views.count,
          total_clicks: clicks.count,
          bounce_rate: total_sessions > 0 ? (bounced.to_f / total_sessions * 100).round(2) : 0,
          conversion_rate: total_sessions > 0 ? (converted.to_f / total_sessions * 100).round(2) : 0,
          total_conversions: converted,
          total_conversion_value: sessions.converted.sum(:conversion_value).to_f,
          avg_session_duration: sessions.average(:duration_seconds)&.round(0) || 0,
          avg_pages_per_session: total_sessions > 0 ? (page_views.count.to_f / total_sessions).round(2) : 0
        }
      end
    end

    def generate_csv(data, type)
      return empty_csv_response(type) if data.empty?

      headers = data.first.keys
      csv_content = CSV.generate do |csv|
        csv << headers
        data.each { |row| csv << row.values }
      end

      {
        data: csv_content,
        filename: "#{type}_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
        content_type: 'text/csv'
      }
    end

    def generate_json(data, type)
      {
        data: {
          type: type,
          exported_at: Time.current.iso8601,
          record_count: data.size,
          records: data
        }.to_json,
        filename: "#{type}_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json",
        content_type: 'application/json'
      }
    end

    def empty_csv_response(type)
      {
        data: "No data available for export\n",
        filename: "#{type}_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
        content_type: 'text/csv'
      }
    end
  end
end
