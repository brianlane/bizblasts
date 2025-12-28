# frozen_string_literal: true

module Analytics
  # Service for providing dashboard analytics data
  class DashboardService
    include Analytics::QueryMonitoring

    attr_reader :business

    # Set custom slow query threshold for dashboard (dashboard queries should be fast)
    self.query_threshold = 0.5

    def initialize(business)
      @business = business
    end

    # Get overview metrics for dashboard widget
    # @param period [Symbol] :today, :last_7_days, :last_30_days
    # @return [Hash] Dashboard metrics
    def overview_metrics(period: :last_30_days)
      date_range = date_range_for(period)
      
      {
        visitors: visitor_metrics(date_range),
        engagement: engagement_metrics(date_range),
        conversions: conversion_metrics(date_range),
        revenue: revenue_metrics(date_range),
        trend: trend_data(date_range),
        top_pages: top_pages_data(date_range),
        traffic_sources: traffic_source_data(date_range)
      }
    end

    # Get real-time metrics
    # @return [Hash] Real-time data
    def realtime_metrics
      {
        active_visitors: active_visitors_count,
        active_sessions: active_sessions,
        recent_page_views: recent_page_views,
        recent_conversions: recent_conversions
      }
    end

    # Get quick stats for the dashboard widget
    # @return [Hash] Quick stats
    def quick_stats
      last_30_days = 30.days.ago..Time.current
      
      visitors = business.visitor_sessions.for_period(30.days.ago, Time.current)
      page_views = business.page_views.for_period(30.days.ago, Time.current)
      
      total_sessions = visitors.count
      bounced = visitors.bounced.count
      
      {
        unique_visitors: visitors.distinct.count(:visitor_fingerprint),
        page_views: page_views.count,
        avg_session_duration: format_duration(visitors.average(:duration_seconds)&.round(0) || 0),
        bounce_rate: total_sessions > 0 ? (bounced.to_f / total_sessions * 100).round(1) : 0,
        conversions: visitors.converted.count,
        conversion_rate: total_sessions > 0 ? 
          (visitors.converted.count.to_f / total_sessions * 100).round(1) : 0
      }
    end

    # Get comparison with previous period
    # @param period [Symbol] Current period
    # @return [Hash] Comparison metrics
    def period_comparison(period: :last_30_days)
      current_range = date_range_for(period)
      previous_range = previous_date_range_for(period)
      
      current = period_metrics(current_range)
      previous = period_metrics(previous_range)
      
      {
        visitors: calculate_change(current[:visitors], previous[:visitors]),
        page_views: calculate_change(current[:page_views], previous[:page_views]),
        sessions: calculate_change(current[:sessions], previous[:sessions]),
        conversions: calculate_change(current[:conversions], previous[:conversions]),
        bounce_rate: calculate_change(current[:bounce_rate], previous[:bounce_rate], inverse: true)
      }
    end

    private

    def date_range_for(period)
      case period
      when :today
        Time.current.beginning_of_day..Time.current
      when :last_7_days
        7.days.ago.beginning_of_day..Time.current
      when :last_30_days
        30.days.ago.beginning_of_day..Time.current
      when :last_90_days
        90.days.ago.beginning_of_day..Time.current
      else
        30.days.ago.beginning_of_day..Time.current
      end
    end

    def previous_date_range_for(period)
      case period
      when :today
        1.day.ago.beginning_of_day..1.day.ago.end_of_day
      when :last_7_days
        14.days.ago.beginning_of_day..7.days.ago
      when :last_30_days
        60.days.ago.beginning_of_day..30.days.ago
      when :last_90_days
        180.days.ago.beginning_of_day..90.days.ago
      else
        60.days.ago.beginning_of_day..30.days.ago
      end
    end

    def visitor_metrics(date_range)
      sessions = business.visitor_sessions.where(session_start: date_range)
      
      {
        total: sessions.distinct.count(:visitor_fingerprint),
        new: sessions.new_visitors.distinct.count(:visitor_fingerprint),
        returning: sessions.returning_visitors.distinct.count(:visitor_fingerprint)
      }
    end

    def engagement_metrics(date_range)
      sessions = business.visitor_sessions.where(session_start: date_range)
      page_views = business.page_views.where(created_at: date_range)
      
      total_sessions = sessions.count
      
      {
        sessions: total_sessions,
        page_views: page_views.count,
        pages_per_session: total_sessions > 0 ? 
          (page_views.count.to_f / total_sessions).round(2) : 0,
        avg_duration: sessions.average(:duration_seconds)&.round(0) || 0,
        avg_duration_formatted: format_duration(sessions.average(:duration_seconds)&.round(0) || 0),
        bounce_rate: total_sessions > 0 ?
          (sessions.bounced.count.to_f / total_sessions * 100).round(1) : 0
      }
    end

    def conversion_metrics(date_range)
      sessions = business.visitor_sessions.where(session_start: date_range)
      clicks = business.click_events.where(created_at: date_range)
      
      total_sessions = sessions.count
      converted = sessions.converted.count
      
      {
        total: converted,
        rate: total_sessions > 0 ? (converted.to_f / total_sessions * 100).round(2) : 0,
        by_type: sessions.converted.group(:conversion_type).count,
        value: sessions.converted.sum(:conversion_value).to_f,
        clicks_to_conversion: clicks.conversions.count
      }
    end

    def revenue_metrics(date_range)
      sessions = business.visitor_sessions.where(session_start: date_range).converted
      bookings = business.bookings.where(created_at: date_range).completed
      
      {
        total_attributed: sessions.sum(:conversion_value).to_f,
        booking_revenue: bookings.joins(:service).sum('services.price').to_f,
        avg_conversion_value: sessions.count > 0 ?
          (sessions.sum(:conversion_value).to_f / sessions.count).round(2) : 0
      }
    end

    def trend_data(date_range)
      # Get daily data for the trend chart
      business.visitor_sessions
        .where(session_start: date_range)
        .group("DATE(session_start)")
        .select("DATE(session_start) as date, COUNT(*) as sessions, COUNT(DISTINCT visitor_fingerprint) as visitors")
        .map { |r| { date: r.date, sessions: r.sessions, visitors: r.visitors } }
    end

    def top_pages_data(date_range, limit: 5)
      business.page_views
        .where(created_at: date_range)
        .group(:page_path)
        .select('page_path, COUNT(*) as views')
        .order('views DESC')
        .limit(limit)
        .map { |r| { path: r.page_path, views: r.views } }
    end

    def traffic_source_data(date_range)
      sessions = business.visitor_sessions.where(session_start: date_range)
      
      sources = {
        direct: sessions.where(first_referrer_domain: [nil, '']).count,
        organic: 0,
        social: 0,
        referral: 0,
        paid: 0
      }
      
      sessions.where.not(first_referrer_domain: [nil, '']).find_each do |session|
        source = categorize_source(session)
        sources[source] += 1
      end
      
      total = sources.values.sum
      
      sources.transform_values do |count|
        {
          count: count,
          percentage: total > 0 ? (count.to_f / total * 100).round(1) : 0
        }
      end
    end

    def period_metrics(date_range)
      sessions = business.visitor_sessions.where(session_start: date_range)
      page_views = business.page_views.where(created_at: date_range)
      
      total = sessions.count
      
      {
        visitors: sessions.distinct.count(:visitor_fingerprint),
        page_views: page_views.count,
        sessions: total,
        conversions: sessions.converted.count,
        bounce_rate: total > 0 ? (sessions.bounced.count.to_f / total * 100).round(1) : 0
      }
    end

    def active_visitors_count
      business.visitor_sessions.active.distinct.count(:visitor_fingerprint)
    end

    def active_sessions
      business.visitor_sessions.active.limit(10).map do |session|
        {
          session_id: session.session_id.first(8),
          current_page: session.page_views.order(created_at: :desc).first&.page_path || 'Unknown',
          duration: format_duration((Time.current - session.session_start).to_i),
          page_views: session.page_view_count
        }
      end
    end

    def recent_page_views(limit: 10)
      business.page_views
        .order(created_at: :desc)
        .limit(limit)
        .map do |pv|
          {
            page: pv.page_path,
            device: pv.device_type,
            time_ago: time_ago_in_words(pv.created_at)
          }
        end
    end

    def recent_conversions(limit: 5)
      business.visitor_sessions
        .converted
        .order(conversion_time: :desc)
        .limit(limit)
        .map do |session|
          {
            type: session.conversion_type,
            value: session.conversion_value.to_f,
            time_ago: time_ago_in_words(session.conversion_time)
          }
        end
    end

    def categorize_source(session)
      if session.utm_medium&.downcase&.in?(%w[cpc ppc paid])
        :paid
      elsif session.first_referrer_domain.blank?
        :direct
      else
        domain = session.first_referrer_domain.to_s.downcase
        
        if %w[google bing yahoo duckduckgo].any? { |se| domain.include?(se) }
          :organic
        elsif %w[facebook twitter instagram linkedin pinterest tiktok].any? { |sn| domain.include?(sn) }
          :social
        else
          :referral
        end
      end
    end

    def calculate_change(current, previous, inverse: false)
      return { value: 0, direction: 'neutral', percentage: 0 } if previous.zero?
      
      change = ((current - previous).to_f / previous * 100).round(1)
      direction = if change > 0
                    inverse ? 'down' : 'up'
                  elsif change < 0
                    inverse ? 'up' : 'down'
                  else
                    'neutral'
                  end
      
      {
        value: change.abs,
        direction: direction,
        percentage: change
      }
    end

    def format_duration(seconds)
      return '0s' if seconds.nil? || seconds.zero?
      
      minutes = seconds / 60
      secs = seconds % 60
      
      if minutes > 0
        "#{minutes}m #{secs}s"
      else
        "#{secs}s"
      end
    end

    def time_ago_in_words(time)
      return 'just now' if time.nil?
      
      seconds = (Time.current - time).to_i
      
      case seconds
      when 0..59 then 'just now'
      when 60..3599 then "#{seconds / 60}m ago"
      when 3600..86399 then "#{seconds / 3600}h ago"
      else "#{seconds / 86400}d ago"
      end
    end
  end
end

