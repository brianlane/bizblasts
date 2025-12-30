# frozen_string_literal: true

module BusinessManager::AnalyticsHelper
  # ============================================================================
  # RFM CUSTOMER SEGMENT HELPERS
  # ============================================================================

  def segment_border_color(segment)
    case segment.to_sym
    when :champions
      'border-l-green-500'
    when :loyal
      'border-l-blue-500'
    when :big_spenders
      'border-l-purple-500'
    when :at_risk
      'border-l-red-500'
    when :lost
      'border-l-gray-500'
    when :new
      'border-l-yellow-500'
    when :occasional
      'border-l-indigo-500'
    when :hibernating
      'border-l-orange-500'
    else
      'border-l-gray-400'
    end
  end

  def segment_text_color(segment)
    case segment.to_sym
    when :champions
      'text-green-600'
    when :loyal
      'text-blue-600'
    when :big_spenders
      'text-purple-600'
    when :at_risk
      'text-red-600'
    when :lost
      'text-gray-600'
    when :new
      'text-yellow-600'
    when :occasional
      'text-indigo-600'
    when :hibernating
      'text-orange-600'
    else
      'text-gray-600'
    end
  end

  def segment_dot_color(segment)
    case segment.to_sym
    when :champions
      'bg-green-500'
    when :loyal
      'bg-blue-500'
    when :big_spenders
      'bg-purple-500'
    when :at_risk
      'bg-red-500'
    when :lost
      'bg-gray-500'
    when :new
      'bg-yellow-500'
    when :occasional
      'bg-indigo-500'
    when :hibernating
      'bg-orange-500'
    else
      'bg-gray-400'
    end
  end

  def segment_description(segment)
    descriptions = {
      champions: 'Your best customers - high value, frequent purchases, recent activity',
      loyal: 'Regular customers with consistent purchase patterns',
      big_spenders: 'High-value customers who spend significantly per transaction',
      at_risk: 'Previously valuable customers showing declining activity',
      lost: 'High-value customers who haven\'t purchased in 180+ days',
      new: 'Recently acquired customers in their first 30 days',
      occasional: 'Infrequent purchasers with lower transaction values',
      hibernating: 'Previously active customers with extended periods of inactivity'
    }
    descriptions[segment.to_sym] || 'Customer segment'
  end

  # ============================================================================
  # STAFF PERFORMANCE HELPERS
  # ============================================================================

  def utilization_color(rate)
    return 'bg-gray-400' if rate.nil?

    if rate < 60
      'bg-yellow-500'
    elsif rate <= 85
      'bg-green-600'
    else
      'bg-red-600'
    end
  end

  def utilization_badge_color(rate)
    return 'bg-gray-100 text-gray-800' if rate.nil?

    if rate < 60
      'bg-yellow-100 text-yellow-800'
    elsif rate <= 85
      'bg-green-100 text-green-800'
    else
      'bg-red-100 text-red-800'
    end
  end

  def utilization_status(rate)
    return 'Unknown' if rate.nil?

    if rate < 60
      'Underutilized'
    elsif rate <= 85
      'Optimal'
    else
      'Overbooked'
    end
  end

  def completion_rate_color(rate)
    return 'text-gray-600' if rate.nil?

    if rate >= 95
      'text-green-600'
    elsif rate >= 85
      'text-blue-600'
    elsif rate >= 75
      'text-yellow-600'
    else
      'text-red-600'
    end
  end

  # ============================================================================
  # MARKETING CHANNEL HELPERS
  # ============================================================================

  def channel_icon_bg(channel)
    case channel.to_s.downcase
    when 'email'
      'bg-blue-100'
    when 'sms'
      'bg-green-100'
    when 'social'
      'bg-purple-100'
    when 'paid_search'
      'bg-yellow-100'
    when 'organic'
      'bg-emerald-100'
    when 'referral'
      'bg-pink-100'
    when 'direct'
      'bg-indigo-100'
    else
      'bg-gray-100'
    end
  end

  def channel_icon_svg(channel)
    case channel.to_s.downcase
    when 'email'
      <<~SVG
        <svg class="w-5 h-5 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"/>
        </svg>
      SVG
    when 'sms'
      <<~SVG
        <svg class="w-5 h-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z"/>
        </svg>
      SVG
    when 'social'
      <<~SVG
        <svg class="w-5 h-5 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 8h2a2 2 0 012 2v6a2 2 0 01-2 2h-2v4l-4-4H9a1.994 1.994 0 01-1.414-.586m0 0L11 14h4a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2v4l.586-.586z"/>
        </svg>
      SVG
    when 'paid_search'
      <<~SVG
        <svg class="w-5 h-5 text-yellow-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
        </svg>
      SVG
    when 'organic'
      <<~SVG
        <svg class="w-5 h-5 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3.055 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.945M8 3.935V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.064M15 20.488V18a2 2 0 012-2h3.064M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
        </svg>
      SVG
    when 'referral'
      <<~SVG
        <svg class="w-5 h-5 text-pink-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"/>
        </svg>
      SVG
    when 'direct'
      <<~SVG
        <svg class="w-5 h-5 text-indigo-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"/>
        </svg>
      SVG
    else
      <<~SVG
        <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"/>
        </svg>
      SVG
    end
  end

  def roi_badge_color(roi)
    return 'bg-gray-100 text-gray-800' if roi.nil?

    if roi >= 200
      'bg-green-100 text-green-800'
    elsif roi >= 100
      'bg-blue-100 text-blue-800'
    elsif roi >= 0
      'bg-yellow-100 text-yellow-800'
    else
      'bg-red-100 text-red-800'
    end
  end

  # ============================================================================
  # TRAFFIC SOURCE HELPERS
  # ============================================================================

  def source_color_bg(source)
    case source.to_s.downcase
    when 'organic'
      'bg-green-100'
    when 'direct'
      'bg-blue-100'
    when 'referral'
      'bg-purple-100'
    when 'social'
      'bg-pink-100'
    when 'paid'
      'bg-yellow-100'
    when 'email'
      'bg-indigo-100'
    else
      'bg-gray-100'
    end
  end

  def source_color_text(source)
    case source.to_s.downcase
    when 'organic'
      'text-green-800'
    when 'direct'
      'text-blue-800'
    when 'referral'
      'text-purple-800'
    when 'social'
      'text-pink-800'
    when 'paid'
      'text-yellow-800'
    when 'email'
      'text-indigo-800'
    else
      'text-gray-800'
    end
  end

  def source_color_bar(source)
    case source.to_s.downcase
    when 'organic'
      'bg-green-500'
    when 'direct'
      'bg-blue-500'
    when 'referral'
      'bg-purple-500'
    when 'social'
      'bg-pink-500'
    when 'paid'
      'bg-yellow-500'
    when 'email'
      'bg-indigo-500'
    else
      'bg-gray-500'
    end
  end

  # ============================================================================
  # REVENUE & FINANCIAL HELPERS
  # ============================================================================

  def revenue_trend_color(trend)
    return 'text-gray-600' if trend.nil? || trend.zero?

    trend.positive? ? 'text-green-600' : 'text-red-600'
  end

  def revenue_trend_icon(trend)
    return '' if trend.nil? || trend.zero?

    if trend.positive?
      <<~SVG
        <svg class="w-5 h-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6"/>
        </svg>
      SVG
    else
      <<~SVG
        <svg class="w-5 h-5 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 17h8m0 0V9m0 8l-8-8-4 4-6-6"/>
        </svg>
      SVG
    end
  end

  def margin_badge_color(margin)
    return 'bg-gray-100 text-gray-800' if margin.nil?

    if margin >= 50
      'bg-green-100 text-green-800'
    elsif margin >= 30
      'bg-blue-100 text-blue-800'
    elsif margin >= 15
      'bg-yellow-100 text-yellow-800'
    else
      'bg-red-100 text-red-800'
    end
  end

  # ============================================================================
  # SUBSCRIPTION METRICS HELPERS
  # ============================================================================

  def mrr_growth_color(growth_rate)
    return 'text-gray-600' if growth_rate.nil? || growth_rate.zero?

    if growth_rate >= 10
      'text-green-600'
    elsif growth_rate >= 5
      'text-blue-600'
    elsif growth_rate.positive?
      'text-yellow-600'
    else
      'text-red-600'
    end
  end

  def churn_rate_badge_color(churn_rate)
    return 'bg-gray-100 text-gray-800' if churn_rate.nil?

    if churn_rate <= 3
      'bg-green-100 text-green-800'
    elsif churn_rate <= 5
      'bg-yellow-100 text-yellow-800'
    elsif churn_rate <= 7
      'bg-orange-100 text-orange-800'
    else
      'bg-red-100 text-red-800'
    end
  end

  def subscription_status_badge(status)
    case status.to_s.downcase
    when 'active'
      content_tag(:span, 'Active', class: 'px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-green-100 text-green-800')
    when 'past_due'
      content_tag(:span, 'Past Due', class: 'px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-yellow-100 text-yellow-800')
    when 'cancelled'
      content_tag(:span, 'Cancelled', class: 'px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-red-100 text-red-800')
    when 'paused'
      content_tag(:span, 'Paused', class: 'px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-gray-100 text-gray-800')
    when 'trialing'
      content_tag(:span, 'Trial', class: 'px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-blue-100 text-blue-800')
    else
      content_tag(:span, status.to_s.titleize, class: 'px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-gray-100 text-gray-800')
    end
  end

  # ============================================================================
  # OPERATIONAL METRICS HELPERS
  # ============================================================================

  def cancellation_rate_color(rate)
    return 'text-gray-600' if rate.nil?

    if rate <= 5
      'text-green-600'
    elsif rate <= 10
      'text-yellow-600'
    else
      'text-red-600'
    end
  end

  def no_show_rate_badge_color(rate)
    return 'bg-gray-100 text-gray-800' if rate.nil?

    if rate <= 5
      'bg-green-100 text-green-800'
    elsif rate <= 10
      'bg-yellow-100 text-yellow-800'
    else
      'bg-red-100 text-red-800'
    end
  end

  # ============================================================================
  # INVENTORY HELPERS
  # ============================================================================

  def stock_level_badge_color(days_remaining)
    return 'bg-gray-100 text-gray-800' if days_remaining.nil?

    if days_remaining <= 3
      'bg-red-100 text-red-800'
    elsif days_remaining <= 7
      'bg-yellow-100 text-yellow-800'
    elsif days_remaining <= 14
      'bg-blue-100 text-blue-800'
    else
      'bg-green-100 text-green-800'
    end
  end

  def turnover_rate_color(rate)
    return 'text-gray-600' if rate.nil?

    if rate >= 12 # Monthly or faster
      'text-green-600'
    elsif rate >= 6 # Bi-monthly
      'text-blue-600'
    elsif rate >= 3 # Quarterly
      'text-yellow-600'
    else
      'text-red-600'
    end
  end

  # ============================================================================
  # PREDICTIVE ANALYTICS HELPERS
  # ============================================================================

  def prediction_confidence_badge(confidence)
    return 'bg-gray-100 text-gray-800' if confidence.nil?

    if confidence >= 85
      'bg-green-100 text-green-800'
    elsif confidence >= 70
      'bg-blue-100 text-blue-800'
    elsif confidence >= 50
      'bg-yellow-100 text-yellow-800'
    else
      'bg-red-100 text-red-800'
    end
  end

  def anomaly_severity_badge(severity)
    case severity.to_s.downcase
    when 'critical'
      content_tag(:span, 'Critical', class: 'px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-red-100 text-red-800')
    when 'high'
      content_tag(:span, 'High', class: 'px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-orange-100 text-orange-800')
    when 'medium'
      content_tag(:span, 'Medium', class: 'px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-yellow-100 text-yellow-800')
    when 'low'
      content_tag(:span, 'Low', class: 'px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-blue-100 text-blue-800')
    else
      content_tag(:span, 'Info', class: 'px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-gray-100 text-gray-800')
    end
  end

  # ============================================================================
  # GENERAL METRIC HELPERS
  # ============================================================================

  def percentage_change_badge(change)
    return content_tag(:span, '0%', class: 'text-gray-600 text-sm') if change.nil? || change.zero?

    color_class = change.positive? ? 'text-green-600' : 'text-red-600'
    icon = change.positive? ? '↑' : '↓'

    content_tag(:span, class: "#{color_class} text-sm font-medium") do
      "#{icon} #{change.abs.round(1)}%"
    end
  end

  def metric_comparison_text(current, previous)
    return 'No previous data' if previous.nil? || previous.zero?

    change = ((current - previous) / previous * 100).round(1)
    direction = change.positive? ? 'increase' : 'decrease'

    "#{change.abs}% #{direction} from previous period"
  end

  def format_large_number(number)
    return '0' if number.nil? || number.zero?

    if number >= 1_000_000
      "#{(number / 1_000_000.0).round(1)}M"
    elsif number >= 1_000
      "#{(number / 1_000.0).round(1)}K"
    else
      number.to_s
    end
  end

  # ============================================================================
  # DATE & TIME HELPERS
  # ============================================================================

  def time_period_label(period)
    case period.to_s
    when '7'
      'Last 7 Days'
    when '30'
      'Last 30 Days'
    when '90'
      'Last 90 Days'
    when '365'
      'Last Year'
    when 'mtd'
      'Month to Date'
    when 'ytd'
      'Year to Date'
    else
      'Custom Period'
    end
  end

  def relative_time_description(days_ago)
    return 'Today' if days_ago.zero?
    return 'Yesterday' if days_ago == 1

    if days_ago <= 7
      "#{days_ago} days ago"
    elsif days_ago <= 30
      "#{(days_ago / 7.0).round} weeks ago"
    elsif days_ago <= 365
      "#{(days_ago / 30.0).round} months ago"
    else
      "#{(days_ago / 365.0).round(1)} years ago"
    end
  end
end
