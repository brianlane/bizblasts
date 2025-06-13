class LoyaltyRedemption < ApplicationRecord
  include TenantScoped
  
  belongs_to :business
  belongs_to :tenant_customer
  belongs_to :loyalty_reward
  belongs_to :booking, optional: true
  belongs_to :order, optional: true
  
  validates :points_redeemed, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true, inclusion: { in: %w[active used expired] }
  validates :discount_code, presence: true, uniqueness: true
  validates :discount_amount_applied, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
  scope :active, -> { where(status: 'active') }
  scope :used, -> { where(status: 'used') }
  scope :expired, -> { where(status: 'expired') }
  scope :recent, -> { order(created_at: :desc) }
  
  before_validation :generate_discount_code, on: :create
  before_create :calculate_discount_amount
  
  def active?
    status == 'active'
  end
  
  def used?
    status == 'used'
  end
  
  def expired?
    status == 'expired'
  end
  
  def mark_used!(transaction_record)
    update!(
      status: 'used',
      booking: transaction_record.is_a?(Booking) ? transaction_record : nil,
      order: transaction_record.is_a?(Order) ? transaction_record : nil
    )
  end
  
  def discount_amount
    # Platform-wide conversion: 100 points = $10
    (points_redeemed / 100) * 10
  end
  
  private
  
  def generate_discount_code
    return if discount_code.present?
    
    # Generate format: LOYALTY-XXXXXX
    loop do
      self.discount_code = "LOYALTY-#{SecureRandom.alphanumeric(6).upcase}"
      break unless LoyaltyRedemption.exists?(discount_code: discount_code)
    end
  end
  
  def calculate_discount_amount
    self.discount_amount_applied = discount_amount
  end
end 