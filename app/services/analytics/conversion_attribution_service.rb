# frozen_string_literal: true

module Analytics
  # Service for attributing conversions to traffic sources and campaigns
  class ConversionAttributionService
    attr_reader :business

    def initialize(business)
      @business = business
    end

    # Attribute a conversion to its traffic source
    # @param session [VisitorSession] The session that converted
    # @param conversion_type [String] Type of conversion (booking, purchase, estimate)
    # @param conversion_value [Numeric] Value of the conversion
    # @return [Hash] Attribution data
    def attribute_conversion(session, conversion_type, conversion_value)
      {
        session_id: session.session_id,
        visitor_fingerprint: session.visitor_fingerprint,
        conversion_type: conversion_type,
        conversion_value: conversion_value,
        attribution: {
          source: determine_source(session),
          medium: determine_medium(session),
          campaign: session.utm_campaign,
          channel: determine_channel(session),
          landing_page: session.entry_page,
          referrer: session.first_referrer_domain
        },
        visitor_type: session.is_returning_visitor ? 'returning' : 'new',
        device_type: session.device_type,
        session_duration: session.duration_seconds,
        pages_viewed: session.page_view_count,
        time_to_conversion: calculate_time_to_conversion(session)
      }
    end

    # Calculate conversion rates by source
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Hash] Conversion rates by source
    def conversion_rates_by_source(start_date: 30.days.ago, end_date: Time.current)
      sessions = business.visitor_sessions.for_period(start_date, end_date)
      
      sources = %w[direct organic social referral paid]
      result = {}
      
      sources.each do |source|
        source_sessions = sessions.select { |s| determine_channel(s) == source }
        total = source_sessions.count
        converted = source_sessions.count(&:converted)
        
        result[source] = {
          sessions: total,
          conversions: converted,
          conversion_rate: total > 0 ? (converted.to_f / total * 100).round(2) : 0,
          total_value: source_sessions.sum(&:conversion_value).to_f
        }
      end
      
      result
    end

    # Get funnel analysis for a conversion path
    # @param conversion_type [String] Type of conversion to analyze
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Hash] Funnel stages with counts
    def funnel_analysis(conversion_type, start_date: 30.days.ago, end_date: Time.current)
      clicks = business.click_events.for_period(start_date, end_date)
      sessions = business.visitor_sessions.for_period(start_date, end_date)
      
      case conversion_type
      when 'booking'
        booking_funnel(clicks, sessions)
      when 'purchase'
        purchase_funnel(clicks, sessions)
      when 'estimate'
        estimate_funnel(clicks, sessions)
      else
        generic_funnel(clicks, sessions)
      end
    end

    # Calculate top converting pages
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @param limit [Integer] Number of pages to return
    # @return [Array<Hash>] Top converting pages
    def top_converting_pages(start_date: 30.days.ago, end_date: Time.current, limit: 10)
      # Get all page views with their session conversion status
      page_views = business.page_views
        .for_period(start_date, end_date)
        .joins("LEFT JOIN visitor_sessions ON page_views.session_id = visitor_sessions.session_id")
        .select('page_views.page_path, visitor_sessions.converted')
      
      # Group by page and calculate conversion rate
      page_stats = page_views.group_by(&:page_path).map do |path, views|
        total = views.count
        converted = views.count { |v| v.converted }
        
        {
          page_path: path,
          views: total,
          conversions: converted,
          conversion_rate: total > 0 ? (converted.to_f / total * 100).round(2) : 0
        }
      end
      
      # Sort by conversion rate (with minimum view threshold)
      page_stats
        .select { |p| p[:views] >= 10 } # Minimum 10 views for statistical relevance
        .sort_by { |p| -p[:conversion_rate] }
        .first(limit)
    end

    # Calculate campaign ROI
    # @param campaign_name [String] UTM campaign name
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Hash] Campaign performance metrics
    def campaign_performance(campaign_name, start_date: 30.days.ago, end_date: Time.current)
      sessions = business.visitor_sessions
        .for_period(start_date, end_date)
        .where(utm_campaign: campaign_name)
      
      {
        campaign: campaign_name,
        sessions: sessions.count,
        unique_visitors: sessions.distinct.count(:visitor_fingerprint),
        conversions: sessions.converted.count,
        conversion_rate: sessions.count > 0 ? 
          (sessions.converted.count.to_f / sessions.count * 100).round(2) : 0,
        total_revenue: sessions.converted.sum(:conversion_value).to_f,
        avg_order_value: sessions.converted.count > 0 ?
          (sessions.converted.sum(:conversion_value) / sessions.converted.count).to_f.round(2) : 0,
        bounce_rate: sessions.count > 0 ?
          (sessions.bounced.count.to_f / sessions.count * 100).round(2) : 0,
        avg_session_duration: sessions.average(:duration_seconds)&.round(0) || 0
      }
    end

    private

    def determine_source(session)
      session.utm_source.presence || 
        determine_source_from_referrer(session.first_referrer_domain)
    end

    def determine_medium(session)
      session.utm_medium.presence || 'organic'
    end

    def determine_channel(session)
      # Check UTM parameters first
      if session.utm_medium.present?
        return 'paid' if session.utm_medium.downcase.in?(%w[cpc ppc paid])
        return 'social' if session.utm_medium.downcase == 'social'
        return 'email' if session.utm_medium.downcase == 'email'
      end
      
      # Check referrer domain
      return 'direct' if session.first_referrer_domain.blank?
      
      domain = session.first_referrer_domain.to_s.downcase
      
      search_engines = %w[google bing yahoo duckduckgo baidu yandex]
      social_networks = %w[facebook twitter instagram linkedin pinterest tiktok youtube reddit]
      
      return 'organic' if search_engines.any? { |se| domain.include?(se) }
      return 'social' if social_networks.any? { |sn| domain.include?(sn) }
      
      'referral'
    end

    def determine_source_from_referrer(referrer_domain)
      return 'direct' if referrer_domain.blank?
      
      # Extract main domain name
      parts = referrer_domain.split('.')
      parts.length >= 2 ? parts[-2] : referrer_domain
    end

    def calculate_time_to_conversion(session)
      return nil unless session.conversion_time.present? && session.session_start.present?
      
      (session.conversion_time - session.session_start).to_i
    end

    def booking_funnel(clicks, sessions)
      {
        stage_1_homepage: sessions.where(entry_page: '/').count,
        stage_2_services_viewed: clicks.service_clicks.distinct.count(:session_id),
        stage_3_booking_started: clicks.where(conversion_type: 'booking_started').distinct.count(:session_id),
        stage_4_booking_completed: sessions.where(conversion_type: 'booking').count
      }
    end

    def purchase_funnel(clicks, sessions)
      {
        stage_1_product_views: clicks.product_clicks.distinct.count(:session_id),
        stage_2_add_to_cart: clicks.where(action: 'add_to_cart').distinct.count(:session_id),
        stage_3_checkout_started: clicks.where(conversion_type: 'checkout_started').distinct.count(:session_id),
        stage_4_purchase_completed: sessions.where(conversion_type: 'purchase').count
      }
    end

    def estimate_funnel(clicks, sessions)
      {
        stage_1_services_viewed: clicks.service_clicks.distinct.count(:session_id),
        stage_2_estimate_page: clicks.where(category: 'estimate').distinct.count(:session_id),
        stage_3_estimate_submitted: sessions.where(conversion_type: 'estimate_request').count
      }
    end

    def generic_funnel(clicks, sessions)
      {
        total_sessions: sessions.count,
        engaged_sessions: sessions.engaged.count,
        interaction_sessions: clicks.distinct.count(:session_id),
        converted_sessions: sessions.converted.count
      }
    end
  end
end

