class PlatformReferral < ApplicationRecord
  belongs_to :referrer_business, class_name: 'Business'
  belongs_to :referred_business, class_name: 'Business'
  has_many :platform_loyalty_transactions, foreign_key: 'related_platform_referral_id', dependent: :destroy
  
  validates :referral_code, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: %w[pending qualified rewarded] }
  
  scope :pending, -> { where(status: 'pending') }
  scope :qualified, -> { where(status: 'qualified') }
  scope :rewarded, -> { where(status: 'rewarded') }
  scope :recent, -> { order(created_at: :desc) }
  
  before_validation :generate_referral_code, on: :create
  
  def qualified?
    status == 'qualified'
  end
  
  def rewarded?
    status == 'rewarded'
  end
  
  def pending?
    status == 'pending'
  end
  
  def mark_qualified!
    update!(
      status: 'qualified',
      qualification_met_at: Time.current
    )
  end
  
  def mark_rewarded!
    update!(
      status: 'rewarded',
      reward_issued_at: Time.current
    )
  end
  
  private
  
  def generate_referral_code
    return if referral_code.present?
    
    # Generate format: BIZ-REFERRER_INITIALS-RANDOM
    referrer_initials = referrer_business&.name&.split&.map(&:first)&.join&.upcase || 'BIZ'
    random_string = SecureRandom.alphanumeric(6).upcase
    
    self.referral_code = "BIZ-#{referrer_initials}-#{random_string}"
    
    # Ensure uniqueness
    while PlatformReferral.exists?(referral_code: referral_code)
      random_string = SecureRandom.alphanumeric(6).upcase
      self.referral_code = "BIZ-#{referrer_initials}-#{random_string}"
    end
  end
end 