class PlatformDiscountCode < ApplicationRecord
  belongs_to :business
  
  validates :code, presence: true, uniqueness: true
  validates :points_redeemed, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :discount_amount, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true, inclusion: { in: %w[active used expired] }
  
  scope :active, -> { where(status: 'active') }
  scope :used, -> { where(status: 'used') }
  scope :expired, -> { where(status: 'expired') }
  scope :recent, -> { order(created_at: :desc) }
  
  before_validation :generate_code, on: :create
  before_validation :set_discount_amount, on: :create
  
  def active?
    status == 'active' && !expired?
  end
  
  def used?
    status == 'used'
  end
  
  def expired?
    expires_at.present? && expires_at < Time.current
  end
  
  def mark_used!
    update!(status: 'used')
  end
  
  def mark_expired!
    update!(status: 'expired')
  end
  
  def can_be_used?
    active? && !expired?
  end
  
  # Calculate discount amount based on points (100 points = $10)
  def self.calculate_discount_amount(points)
    (points / 100) * 10
  end
  
  def is_percentage_discount?
    points_redeemed == 0 # Referral rewards are percentage discounts
  end
  
  def is_fixed_amount_discount?
    points_redeemed > 0 # Loyalty redemptions are fixed amount discounts
  end
  
  def display_discount
    if is_percentage_discount?
      "#{discount_amount.to_i}% off"
    else
      "$#{discount_amount.to_i} off"
    end
  end
  
  # Get available point redemption options (100, 200, 300, ..., 1000)
  def self.redemption_options
    (1..10).map do |multiplier|
      points = multiplier * 100
      {
        points: points,
        discount_amount: calculate_discount_amount(points),
        description: "$#{multiplier * 10} off subscription"
      }
    end
  end
  
  # Find valid redemption amounts for a business
  def self.available_redemptions_for_business(business)
    current_points = business.current_platform_loyalty_points
    redemption_options.select { |option| option[:points] <= current_points }
  end
  
  private
  
  def generate_code
    return if code.present?
    
    # Generate format: BIZBLASTS-RANDOM
    random_string = SecureRandom.alphanumeric(8).upcase
    self.code = "BIZBLASTS-#{random_string}"
    
    # Ensure uniqueness
    while PlatformDiscountCode.exists?(code: code)
      random_string = SecureRandom.alphanumeric(8).upcase
      self.code = "BIZBLASTS-#{random_string}"
    end
  end
  
  def set_discount_amount
    return if discount_amount.present?
    self.discount_amount = self.class.calculate_discount_amount(points_redeemed)
  end
end 