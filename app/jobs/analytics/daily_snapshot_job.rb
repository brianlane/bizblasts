# frozen_string_literal: true

module Analytics
  # Job for generating daily analytics snapshots
  # Runs daily at 2 AM to generate previous day's summary
  class DailySnapshotJob < ApplicationJob
    queue_as :analytics

    def perform(date = nil)
      date ||= Date.yesterday
      Rails.logger.info "[DailySnapshot] Generating snapshots for #{date}..."
      
      # Generate snapshot for each active business
      Business.active.find_each do |business|
        generate_snapshot(business, date)
      rescue StandardError => e
        Rails.logger.error "[DailySnapshot] Error generating snapshot for business #{business.id}: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
      end
      
      Rails.logger.info "[DailySnapshot] Daily snapshot generation complete"
    end

    private

    def generate_snapshot(business, date)
      ActsAsTenant.with_tenant(business) do
        # Skip if snapshot already exists
        existing = business.analytics_snapshots.find_by(
          snapshot_type: 'daily',
          period_start: date,
          period_end: date
        )
        
        if existing
          Rails.logger.debug "[DailySnapshot] Snapshot already exists for business #{business.id} on #{date}"
          return
        end
        
        # Calculate metrics for the date
        metrics = calculate_metrics(business, date)
        
        # Create snapshot
        business.analytics_snapshots.create!(
          snapshot_type: 'daily',
          period_start: date,
          period_end: date,
          generated_at: Time.current,
          **metrics
        )
        
        Rails.logger.info "[DailySnapshot] Created snapshot for business #{business.id} on #{date}"
      end
    end

    def calculate_metrics(business, date)
      date_range = date.beginning_of_day..date.end_of_day
      
      sessions = business.visitor_sessions.where(session_start: date_range)
      page_views = business.page_views.where(created_at: date_range)
      clicks = business.click_events.where(created_at: date_range)
      
      total_sessions = sessions.count
      
      {
        unique_visitors: sessions.distinct.count(:visitor_fingerprint),
        total_page_views: page_views.count,
        total_sessions: total_sessions,
        bounce_rate: calculate_bounce_rate(sessions, total_sessions),
        avg_session_duration: sessions.where.not(duration_seconds: nil).average(:duration_seconds)&.round(0) || 0,
        pages_per_session: total_sessions > 0 ? (page_views.count.to_f / total_sessions).round(2) : 0,
        total_clicks: clicks.count,
        unique_pages_viewed: page_views.distinct.count(:page_path),
        total_conversions: sessions.converted.count,
        conversion_rate: calculate_conversion_rate(sessions, total_sessions),
        total_conversion_value: sessions.converted.sum(:conversion_value).to_f,
        booking_metrics: calculate_booking_metrics(business, date_range),
        product_metrics: calculate_product_metrics(business, date_range),
        service_metrics: calculate_service_metrics(business, date_range),
        estimate_metrics: calculate_estimate_metrics(business, date_range),
        traffic_sources: calculate_traffic_sources(sessions),
        top_referrers: calculate_top_referrers(sessions),
        top_pages: calculate_top_pages(page_views),
        device_breakdown: calculate_device_breakdown(sessions),
        geo_breakdown: calculate_geo_breakdown(sessions),
        campaign_metrics: calculate_campaign_metrics(sessions)
      }
    end

    def calculate_bounce_rate(sessions, total)
      return 0.0 if total.zero?
      (sessions.bounced.count.to_f / total * 100).round(2)
    end

    def calculate_conversion_rate(sessions, total)
      return 0.0 if total.zero?
      (sessions.converted.count.to_f / total * 100).round(2)
    end

    def calculate_booking_metrics(business, date_range)
      bookings = business.bookings.where(created_at: date_range)
      
      {
        total: bookings.count,
        completed: bookings.completed.count,
        cancelled: bookings.cancelled.count,
        revenue: bookings.completed.joins(:service).sum('services.price').to_f,
        avg_value: bookings.completed.any? ? 
          (bookings.completed.joins(:service).sum('services.price').to_f / bookings.completed.count).round(2) : 0
      }
    end

    def calculate_product_metrics(business, date_range)
      orders = business.orders.where(created_at: date_range)
      product_clicks = business.click_events.where(created_at: date_range, category: 'product')
      
      {
        views: product_clicks.count,
        purchases: orders.where(status: [:completed, :delivered]).count,
        revenue: orders.where(status: [:completed, :delivered]).sum(:total).to_f,
        conversion_rate: product_clicks.count > 0 ?
          (orders.count.to_f / product_clicks.distinct.count(:session_id) * 100).round(2) : 0
      }
    end

    def calculate_service_metrics(business, date_range)
      service_clicks = business.click_events.where(created_at: date_range, category: 'service')
      bookings = business.bookings.where(created_at: date_range)
      
      {
        views: service_clicks.count,
        bookings: bookings.count,
        conversion_rate: service_clicks.count > 0 ?
          (bookings.count.to_f / service_clicks.distinct.count(:session_id) * 100).round(2) : 0
      }
    end

    def calculate_estimate_metrics(business, date_range)
      estimates = business.estimates.where(created_at: date_range)
      
      sent = estimates.sent.count
      viewed = estimates.viewed.count
      approved = estimates.approved.count
      total_value = estimates.sum(:total).to_f
      
      {
        sent: sent,
        viewed: viewed,
        approved: approved,
        total_value: total_value,
        conversion_rate: sent > 0 ? (approved.to_f / sent * 100).round(2) : 0
      }
    end

    def calculate_traffic_sources(sessions)
      sources = { direct: 0, organic: 0, social: 0, referral: 0, paid: 0 }
      
      sessions.find_each do |session|
        source = categorize_source(session)
        sources[source] += 1
      end
      
      total = sources.values.sum
      sources.transform_values { |v| total > 0 ? (v.to_f / total * 100).round(1) : 0 }
    end

    def calculate_top_referrers(sessions, limit: 10)
      sessions
        .where.not(first_referrer_domain: [nil, ''])
        .group(:first_referrer_domain)
        .order('count_all DESC')
        .limit(limit)
        .count
        .map { |domain, count| { domain: domain, visits: count } }
    end

    def calculate_top_pages(page_views, limit: 10)
      page_views
        .group(:page_path)
        .select('page_path, COUNT(*) as views, AVG(time_on_page) as avg_time')
        .order('views DESC')
        .limit(limit)
        .map do |pv|
          {
            path: pv.page_path,
            views: pv.views,
            avg_time: pv.avg_time&.round(0) || 0
          }
        end
    end

    def calculate_device_breakdown(sessions)
      total = sessions.count
      return { desktop: 0, mobile: 0, tablet: 0 } if total.zero?
      
      breakdown = sessions.group(:device_type).count
      
      {
        desktop: ((breakdown['desktop'] || 0).to_f / total * 100).round(1),
        mobile: ((breakdown['mobile'] || 0).to_f / total * 100).round(1),
        tablet: ((breakdown['tablet'] || 0).to_f / total * 100).round(1)
      }
    end

    def calculate_geo_breakdown(sessions)
      sessions
        .where.not(country: nil)
        .group(:country)
        .order('count_all DESC')
        .limit(10)
        .count
    end

    def calculate_campaign_metrics(sessions)
      sessions
        .where.not(utm_campaign: nil)
        .group(:utm_campaign)
        .select('utm_campaign, COUNT(*) as visits, SUM(CASE WHEN converted THEN 1 ELSE 0 END) as conversions, SUM(conversion_value) as revenue')
        .each_with_object({}) do |session, hash|
          hash[session.utm_campaign] = {
            visits: session.visits,
            conversions: session.conversions,
            revenue: session.revenue.to_f
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
  end
end

