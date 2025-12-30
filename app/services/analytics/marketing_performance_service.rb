# frozen_string_literal: true

module Analytics
  # Service for marketing campaign performance and ROI analysis
  class MarketingPerformanceService
    include Analytics::QueryMonitoring

    attr_reader :business

    self.query_threshold = 1.0

    def initialize(business)
      @business = business
    end

    # Campaign ROI calculation
    def campaign_roi(campaign_id, period = nil)
      campaign = business.marketing_campaigns.find(campaign_id)

      # Get attributed conversions via UTM tracking
      attributed_sessions = if period
                             business.visitor_sessions
                                     .where(utm_campaign: campaign.campaign_code, created_at: period.ago..Time.current)
                           else
                             business.visitor_sessions
                                     .where(utm_campaign: campaign.campaign_code)
                           end

      # Calculate revenue from converted sessions
      attributed_revenue = attributed_sessions.converted.sum(:conversion_value).to_f

      # Get campaign cost
      cost = campaign.cost || 0

      # Calculate metrics
      conversions = attributed_sessions.converted.count
      total_sessions = attributed_sessions.count

      {
        campaign_id: campaign.id,
        campaign_name: campaign.name,
        revenue: attributed_revenue.round(2),
        cost: cost.round(2),
        roi: cost > 0 ? (((attributed_revenue - cost) / cost) * 100).round(2) : nil,
        conversions: conversions,
        total_sessions: total_sessions,
        conversion_rate: total_sessions > 0 ? ((conversions.to_f / total_sessions) * 100).round(2) : 0,
        cost_per_conversion: conversions > 0 ? (cost / conversions).round(2) : 0,
        revenue_per_session: total_sessions > 0 ? (attributed_revenue / total_sessions).round(2) : 0
      }
    end

    # All campaigns performance summary
    def campaigns_summary(period = 30.days)
      campaigns = business.marketing_campaigns.where(created_at: period.ago..Time.current)

      campaigns.map do |campaign|
        campaign_roi(campaign.id, period)
      end.sort_by { |c| -c[:roi].to_f }
    end

    # Email campaign performance
    def email_campaign_performance(period = 30.days)
      campaigns = business.marketing_campaigns
                          .where(campaign_type: :email, created_at: period.ago..Time.current)

      campaigns.map do |campaign|
        sent = campaign.sent_count || 0
        opened = campaign.opened_count || 0
        clicked = campaign.clicked_count || 0
        conversions = campaign.conversions_count || 0

        {
          campaign_id: campaign.id,
          campaign_name: campaign.name,
          sent: sent,
          opened: opened,
          clicked: clicked,
          conversions: conversions,
          open_rate: sent > 0 ? ((opened.to_f / sent) * 100).round(2) : 0,
          click_rate: opened > 0 ? ((clicked.to_f / opened) * 100).round(2) : 0,
          conversion_rate: sent > 0 ? ((conversions.to_f / sent) * 100).round(2) : 0,
          revenue: calculate_campaign_revenue(campaign)
        }
      end.sort_by { |c| -c[:conversion_rate] }
    end

    # SMS campaign performance
    def sms_campaign_performance(period = 30.days)
      campaigns = business.marketing_campaigns
                          .where(campaign_type: :sms, created_at: period.ago..Time.current)

      campaigns.map do |campaign|
        sent = campaign.sent_count || 0
        conversions = campaign.conversions_count || 0

        {
          campaign_id: campaign.id,
          campaign_name: campaign.name,
          sent: sent,
          conversions: conversions,
          conversion_rate: sent > 0 ? ((conversions.to_f / sent) * 100).round(2) : 0,
          revenue: calculate_campaign_revenue(campaign)
        }
      end.sort_by { |c| -c[:conversion_rate] }
    end

    # Promotion effectiveness tracking
    def promotion_effectiveness(promotion_id)
      promotion = business.promotions.find(promotion_id)

      # Get redemptions
      redemptions = business.orders.where(promotion_code: promotion.code)
      redemption_count = redemptions.count

      # Calculate revenue impact
      total_discount = redemptions.sum(&:discount_amount).to_f
      total_revenue = redemptions.sum(:total_amount).to_f

      # Get baseline revenue (average revenue without promotion)
      baseline_period = 30.days
      baseline_orders = business.orders
                                .where.not(promotion_code: promotion.code)
                                .where(created_at: baseline_period.ago..Time.current)
      avg_baseline_revenue = baseline_orders.any? ? baseline_orders.average(:total_amount).to_f : 0

      # Calculate incremental revenue
      incremental_revenue = redemptions.sum do |order|
        order.total_amount - (avg_baseline_revenue * 0.8) # Assume 20% wouldn't purchase without promo
      end

      {
        promotion_id: promotion.id,
        promotion_name: promotion.name,
        promotion_code: promotion.code,
        redemption_count: redemption_count,
        total_discount: total_discount.round(2),
        total_revenue: total_revenue.round(2),
        incremental_revenue: incremental_revenue.round(2),
        redemption_rate: calculate_redemption_rate(promotion),
        avg_order_value: redemption_count > 0 ? (total_revenue / redemption_count).round(2) : 0,
        roi: total_discount > 0 ? ((incremental_revenue / total_discount) * 100).round(2) : nil
      }
    end

    # All promotions summary
    def promotions_summary(period = 30.days)
      promotions = business.promotions.where(created_at: period.ago..Time.current)

      promotions.map do |promotion|
        promotion_effectiveness(promotion.id)
      end.sort_by { |p| -p[:incremental_revenue] }
    end

    # Referral program performance
    def referral_program_metrics(period = 30.days)
      referrals = business.referrals.where(created_at: period.ago..Time.current)

      successful_referrals = referrals.where(status: :converted)
      total_referrals = referrals.count

      # Calculate revenue from referrals
      referred_customers = business.tenant_customers.where(referral_id: successful_referrals.pluck(:id))
      referral_revenue = referred_customers.sum(&:total_revenue)

      {
        total_referrals: total_referrals,
        successful_referrals: successful_referrals.count,
        conversion_rate: total_referrals > 0 ? ((successful_referrals.count.to_f / total_referrals) * 100).round(2) : 0,
        total_revenue: referral_revenue.round(2),
        avg_revenue_per_referral: successful_referrals.any? ? (referral_revenue / successful_referrals.count).round(2) : 0,
        top_referrers: top_referrers(period, 10)
      }
    end

    # Customer acquisition by source
    def acquisition_by_source(period = 30.days)
      sessions = business.visitor_sessions
                         .where(created_at: period.ago..Time.current)
                         .converted

      # Group by traffic source
      sources = {
        direct: 0,
        organic: 0,
        social: 0,
        referral: 0,
        paid: 0,
        email: 0
      }

      sessions.each do |session|
        source = categorize_traffic_source(session)
        sources[source] += 1
      end

      # Calculate cost per acquisition for paid sources
      all_campaigns = business.marketing_campaigns
                               .where(created_at: period.ago..Time.current)
      total_paid_cost = all_campaigns.sum(:cost).to_f

      sources_data = sources.map do |source, count|
        {
          source: source.to_s.titleize,
          acquisitions: count,
          percentage: sessions.count > 0 ? ((count.to_f / sessions.count) * 100).round(1) : 0,
          cost_per_acquisition: (source == :paid && count > 0) ? (total_paid_cost / count).round(2) : nil
        }
      end

      sources_data.sort_by { |s| -s[:acquisitions] }
    end

    # Marketing spend efficiency
    def marketing_spend_efficiency(period = 30.days)
      campaigns = business.marketing_campaigns.where(created_at: period.ago..Time.current)

      total_spend = campaigns.sum(:cost).to_f
      total_revenue = campaigns.sum { |c| calculate_campaign_revenue(c) }
      total_conversions = campaigns.sum(:conversions_count).to_i

      {
        total_spend: total_spend.round(2),
        total_revenue: total_revenue.round(2),
        total_conversions: total_conversions,
        cost_per_conversion: total_conversions > 0 ? (total_spend / total_conversions).round(2) : 0,
        roas: total_spend > 0 ? (total_revenue / total_spend).round(2) : 0, # Return on Ad Spend
        roi: total_spend > 0 ? (((total_revenue - total_spend) / total_spend) * 100).round(2) : 0
      }
    end

    # Channel performance comparison
    def channel_performance(period = 30.days)
      channels = [:email, :sms, :social, :paid, :organic]

      channels.map do |channel|
        sessions = business.visitor_sessions
                           .where(created_at: period.ago..Time.current)

        channel_sessions = filter_sessions_by_channel(sessions, channel)
        conversions = channel_sessions.converted.count

        {
          channel: channel.to_s.titleize,
          sessions: channel_sessions.count,
          conversions: conversions,
          conversion_rate: channel_sessions.count > 0 ? ((conversions.to_f / channel_sessions.count) * 100).round(2) : 0,
          revenue: channel_sessions.converted.sum(:conversion_value).to_f.round(2)
        }
      end.sort_by { |c| -c[:revenue] }
    end

    # Attribution analysis (first-touch vs last-touch)
    def attribution_analysis(period = 30.days)
      converted_sessions = business.visitor_sessions
                                   .where(created_at: period.ago..Time.current)
                                   .converted

      first_touch = {}
      last_touch = {}

      converted_sessions.each do |session|
        # First touch: from first_referrer_domain
        first_source = categorize_first_touch(session)
        first_touch[first_source] ||= { count: 0, revenue: 0 }
        first_touch[first_source][:count] += 1
        first_touch[first_source][:revenue] += session.conversion_value.to_f

        # Last touch: from current source
        last_source = categorize_traffic_source(session)
        last_touch[last_source] ||= { count: 0, revenue: 0 }
        last_touch[last_source][:count] += 1
        last_touch[last_source][:revenue] += session.conversion_value.to_f
      end

      {
        first_touch: format_attribution_data(first_touch),
        last_touch: format_attribution_data(last_touch)
      }
    end

    private

    def calculate_campaign_revenue(campaign)
      business.visitor_sessions
              .where(utm_campaign: campaign.campaign_code)
              .converted
              .sum(:conversion_value).to_f
    end

    def calculate_redemption_rate(promotion)
      # Total potential customers who saw the promotion
      views = business.page_views
                      .where("page_path LIKE ?", "%promo=#{promotion.code}%")
                      .distinct
                      .count(:session_id)

      redemptions = business.orders.where(promotion_code: promotion.code).count

      views > 0 ? ((redemptions.to_f / views) * 100).round(2) : 0
    end

    def top_referrers(period, limit)
      referrers = business.referrals
                          .where(created_at: period.ago..Time.current, status: :converted)
                          .group(:referrer_id)
                          .count

      referrers.map do |referrer_id, count|
        referrer = business.tenant_customers.find_by(id: referrer_id)
        next unless referrer

        {
          referrer_name: referrer.full_name,
          referrals: count
        }
      end.compact.sort_by { |r| -r[:referrals] }.first(limit)
    end

    def categorize_traffic_source(session)
      return :paid if session.utm_medium&.downcase&.in?(['cpc', 'ppc', 'paid'])
      return :email if session.utm_medium&.downcase == 'email'
      return :social if session.first_referrer_domain&.match?(/facebook|twitter|instagram|linkedin|pinterest|tiktok/i)
      return :organic if session.first_referrer_domain&.match?(/google|bing|yahoo|duckduckgo/i)
      return :referral if session.first_referrer_domain.present?

      :direct
    end

    def categorize_first_touch(session)
      return :paid if session.first_utm_medium&.downcase&.in?(['cpc', 'ppc', 'paid'])
      return :email if session.first_utm_medium&.downcase == 'email'
      return :social if session.first_referrer_domain&.match?(/facebook|twitter|instagram|linkedin|pinterest|tiktok/i)
      return :organic if session.first_referrer_domain&.match?(/google|bing|yahoo|duckduckgo/i)
      return :referral if session.first_referrer_domain.present?

      :direct
    end

    def filter_sessions_by_channel(sessions, channel)
      case channel
      when :email
        sessions.where("utm_medium = 'email'")
      when :sms
        sessions.where("utm_medium = 'sms'")
      when :social
        sessions.where("first_referrer_domain ~ 'facebook|twitter|instagram|linkedin|pinterest|tiktok'")
      when :paid
        sessions.where("LOWER(utm_medium) IN ('cpc', 'ppc', 'paid')")
      when :organic
        sessions.where("first_referrer_domain ~ 'google|bing|yahoo|duckduckgo'")
      else
        sessions
      end
    end

    def format_attribution_data(data)
      data.map do |source, metrics|
        {
          source: source.to_s.titleize,
          conversions: metrics[:count],
          revenue: metrics[:revenue].round(2)
        }
      end.sort_by { |d| -d[:revenue] }
    end
  end
end
