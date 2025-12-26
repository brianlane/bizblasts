# frozen_string_literal: true

module AnalyticsHelper
  # Returns Tailwind CSS class for traffic source color
  def source_color(source)
    colors = {
      direct: 'bg-indigo-500',
      organic: 'bg-green-500',
      social: 'bg-blue-500',
      referral: 'bg-amber-500',
      paid: 'bg-red-500'
    }
    colors[source.to_sym] || 'bg-gray-500'
  end

  # Format number with K/M suffix for large numbers
  def format_number_short(number)
    return '0' if number.nil? || number.zero?
    
    if number >= 1_000_000
      "#{(number / 1_000_000.0).round(1)}M"
    elsif number >= 1_000
      "#{(number / 1_000.0).round(1)}K"
    else
      number.to_s
    end
  end

  # Format duration in human-readable form
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

  # Get trend indicator class and icon
  def trend_indicator(value, inverse: false)
    return { class: 'text-gray-500', icon: 'minus', label: 'No change' } if value.zero?
    
    is_positive = value > 0
    is_positive = !is_positive if inverse
    
    if is_positive
      { class: 'text-green-600', icon: 'arrow-up', label: "+#{value.abs}%" }
    else
      { class: 'text-red-600', icon: 'arrow-down', label: "-#{value.abs}%" }
    end
  end

  # SEO score color class
  def seo_score_color(score)
    case score
    when 0..30 then 'text-red-600 bg-red-100'
    when 31..60 then 'text-yellow-600 bg-yellow-100'
    when 61..80 then 'text-blue-600 bg-blue-100'
    when 81..100 then 'text-green-600 bg-green-100'
    else 'text-gray-600 bg-gray-100'
    end
  end

  # SEO suggestion priority badge
  def priority_badge(priority)
    case priority
    when 'high'
      content_tag(:span, 'High', class: 'px-2 py-1 text-xs font-medium rounded-full bg-red-100 text-red-800')
    when 'medium'
      content_tag(:span, 'Medium', class: 'px-2 py-1 text-xs font-medium rounded-full bg-yellow-100 text-yellow-800')
    when 'low'
      content_tag(:span, 'Low', class: 'px-2 py-1 text-xs font-medium rounded-full bg-green-100 text-green-800')
    else
      content_tag(:span, priority.to_s.capitalize, class: 'px-2 py-1 text-xs font-medium rounded-full bg-gray-100 text-gray-800')
    end
  end

  # Ranking position badge
  def ranking_badge(position)
    case position
    when 1..3
      content_tag(:span, "Top 3 (##{position})", class: 'px-2 py-1 text-xs font-medium rounded-full bg-green-100 text-green-800')
    when 4..10
      content_tag(:span, "Page 1 (##{position})", class: 'px-2 py-1 text-xs font-medium rounded-full bg-blue-100 text-blue-800')
    when 11..20
      content_tag(:span, "Page 2 (##{position})", class: 'px-2 py-1 text-xs font-medium rounded-full bg-yellow-100 text-yellow-800')
    when 21..50
      content_tag(:span, "##{position}", class: 'px-2 py-1 text-xs font-medium rounded-full bg-orange-100 text-orange-800')
    else
      content_tag(:span, ">50", class: 'px-2 py-1 text-xs font-medium rounded-full bg-gray-100 text-gray-800')
    end
  end

  # Device type icon
  def device_icon(device_type)
    case device_type.to_s.downcase
    when 'desktop'
      '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"/></svg>'.html_safe
    when 'mobile'
      '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z"/></svg>'.html_safe
    when 'tablet'
      '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 18h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z"/></svg>'.html_safe
    else
      '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"/></svg>'.html_safe
    end
  end
end

