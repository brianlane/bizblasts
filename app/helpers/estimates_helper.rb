module EstimatesHelper
  def estimate_status_badge(status)
    case status.to_s
    when 'draft'
      'bg-gray-100 text-gray-800'
    when 'sent'
      'bg-blue-100 text-blue-800'
    when 'viewed'
      'bg-yellow-100 text-yellow-800'
    when 'approved'
      'bg-green-100 text-green-800'
    when 'declined'
      'bg-red-100 text-red-800'
    when 'cancelled'
      'bg-gray-100 text-gray-800'
    else
      'bg-gray-100 text-gray-800'
    end
  end

  def render_estimate_status_badge(estimate)
    status = estimate.status.to_s
    
    badge_styles = case status
    when 'draft'
      { bg: 'bg-gray-100', text: 'text-gray-700', border: 'border-gray-300', icon_bg: 'bg-gray-400' }
    when 'sent'
      { bg: 'bg-blue-100', text: 'text-blue-700', border: 'border-blue-300', icon_bg: 'bg-blue-500' }
    when 'viewed'
      { bg: 'bg-yellow-100', text: 'text-yellow-700', border: 'border-yellow-300', icon_bg: 'bg-yellow-500' }
    when 'pending_payment'
      { bg: 'bg-orange-100', text: 'text-orange-700', border: 'border-orange-300', icon_bg: 'bg-orange-500' }
    when 'approved'
      { bg: 'bg-green-100', text: 'text-green-700', border: 'border-green-300', icon_bg: 'bg-green-500' }
    when 'declined'
      { bg: 'bg-red-100', text: 'text-red-700', border: 'border-red-300', icon_bg: 'bg-red-500' }
    when 'cancelled'
      { bg: 'bg-gray-100', text: 'text-gray-600', border: 'border-gray-300', icon_bg: 'bg-gray-400' }
    else
      { bg: 'bg-gray-100', text: 'text-gray-700', border: 'border-gray-300', icon_bg: 'bg-gray-400' }
    end

    icon = case status
    when 'draft'
      '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"/>'
    when 'sent'
      '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"/>'
    when 'viewed'
      '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"/>'
    when 'pending_payment'
      '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>'
    when 'approved'
      '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>'
    when 'declined'
      '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"/>'
    when 'cancelled'
      '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636"/>'
    else
      '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>'
    end

    content_tag(:span, class: "inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium #{badge_styles[:bg]} #{badge_styles[:text]} border #{badge_styles[:border]}") do
      svg = content_tag(:svg, class: "w-3 h-3 mr-1", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
        icon.html_safe
      end
      svg + status.humanize
    end
  end
end

