# frozen_string_literal: true

# Concern for handling booking statuses
module BookingStatus
  extend ActiveSupport::Concern

  included do
    # Define booking statuses
    enum :status, {
      pending: 0,
      confirmed: 1,
      cancelled: 2,
      completed: 3,
      no_show: 4
    }
    
    validates :status, presence: true
  end
  
  # Check if the given status is valid
  def valid_status?(status)
    self.class.statuses.include?(status.to_s)
  end
  
  # Cancel the booking and set reason
  def cancel!(reason = nil)
    update(status: :cancelled, cancellation_reason: reason)
  end
  
  # Check if the booking can be cancelled
  def can_cancel?
    !%w[cancelled completed].include?(status) && start_time > Time.current
  end
  
  # Check if the booking is in the past
  def past?
    end_time < Time.current
  end
end 