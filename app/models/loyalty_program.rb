class LoyaltyProgram < ApplicationRecord
  include TenantScoped
  
  has_many :loyalty_rewards, dependent: :destroy
  
  validates :name, presence: true
  validates :points_name, presence: true
  validates :points_for_booking, numericality: { greater_than_or_equal_to: 0 }
  validates :points_for_referral, numericality: { greater_than_or_equal_to: 0 }
  validates :points_per_dollar, numericality: { greater_than_or_equal_to: 0 }
  validates :active, inclusion: { in: [true, false] }
  
  scope :active, -> { where(active: true) }
  
  def award_booking_points(customer, booking)
    return unless active?
    
    points = points_for_booking
    if booking.amount.present?
      points += (booking.amount * points_per_dollar).to_i
    end
    
    # Placeholder: actual implementation would create a LoyaltyTransaction
    # customer.add_loyalty_points(points, "Booking ##{booking.id}")
  end
  
  def award_referral_points(customer, referred_customer)
    return unless active?
    
    # Placeholder: actual implementation would create a LoyaltyTransaction
    # customer.add_loyalty_points(points_for_referral, "Referral: #{referred_customer.name}")
  end
end
