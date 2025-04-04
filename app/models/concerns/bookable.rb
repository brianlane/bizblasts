module Bookable
  extend ActiveSupport::Concern

  included do
    has_many :bookings, as: :bookable, dependent: :destroy
    
    # Common validations for bookable items
    validates :name, presence: true
    validates :available_from, presence: true
    validates :available_to, presence: true
  end
  
  def available?(start_time, end_time)
    # Placeholder for availability logic
    return false if start_time < Time.current
    return false if start_time < available_from || end_time > available_to
    
    # Check existing bookings (simplified example)
    !bookings.where('start_time <= ? AND end_time >= ?', end_time, start_time).exists?
  end
end
