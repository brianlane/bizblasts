class PlatformLoyaltyTransaction < ApplicationRecord
  belongs_to :business
  belongs_to :related_platform_referral, class_name: 'PlatformReferral', optional: true
  
  validates :transaction_type, presence: true, inclusion: { in: %w[earned redeemed expired adjusted] }
  validates :points_amount, presence: true, numericality: { other_than: 0 }
  validates :description, presence: true
  
  scope :earned, -> { where(transaction_type: 'earned') }
  scope :redeemed, -> { where(transaction_type: 'redeemed') }
  scope :expired, -> { where(transaction_type: 'expired') }
  scope :adjusted, -> { where(transaction_type: 'adjusted') }
  scope :recent, -> { order(created_at: :desc) }
  
  def earned?
    transaction_type == 'earned'
  end
  
  def redeemed?
    transaction_type == 'redeemed'
  end
  
  def points_value
    points_amount
  end
  
  def display_amount
    if points_amount > 0
      "+#{points_amount}"
    else
      points_amount.to_s
    end
  end
end 