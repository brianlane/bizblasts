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
end

