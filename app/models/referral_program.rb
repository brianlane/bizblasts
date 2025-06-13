class ReferralProgram < ApplicationRecord
  include TenantScoped
  
  belongs_to :business
  has_many :referrals, dependent: :destroy
  
  validates :referrer_reward_type, presence: true, inclusion: { in: %w[points] }
  validates :referrer_reward_value, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :referral_code_discount_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :min_purchase_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :active, inclusion: { in: [true, false] }
  
  scope :active, -> { where(active: true) }
  
  def referrer_reward_points?
    referrer_reward_type == 'points'
  end
  
  def referrer_reward_discount?
    false # Referrer rewards are always points now
  end
  
  # Keep these methods for backward compatibility, but they now refer to the discount amount
  def referred_reward_points?
    false # Referred customers get discount via the referral code
  end
  
  def referred_reward_discount?
    true # Referral codes always provide discount
  end
  
  def referred_reward_value
    referral_code_discount_amount # For backward compatibility
  end
  
  def minimum_purchase_required?
    min_purchase_amount.present? && min_purchase_amount > 0
  end
end 