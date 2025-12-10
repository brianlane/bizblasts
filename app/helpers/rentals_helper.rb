module RentalsHelper
  def rental_status_badge(status)
    case status.to_s
    when 'pending_deposit'
      'bg-amber-100 text-amber-800'
    when 'deposit_paid'
      'bg-indigo-100 text-indigo-800'
    when 'checked_out'
      'bg-blue-100 text-blue-800'
    when 'overdue'
      'bg-red-100 text-red-800'
    when 'returned'
      'bg-teal-100 text-teal-800'
    when 'completed'
      'bg-green-100 text-green-800'
    when 'cancelled'
      'bg-gray-100 text-gray-800'
    else
      'bg-gray-100 text-gray-800'
    end
  end
end

