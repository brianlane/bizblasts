class Promotion < ApplicationRecord
  include TenantScoped
  
  has_many :promotion_redemptions, dependent: :destroy
  has_many :customers, through: :promotion_redemptions
  
  validates :name, presence: true
  validates :code, presence: true, uniqueness: { scope: :business_id }
  validates :starts_at, presence: true
  validates :ends_at, presence: true
  validates :discount_type, presence: true
  validates :discount_value, presence: true, numericality: { greater_than: 0 }
  
  enum :discount_type, {
    percentage: 0,
    fixed_amount: 1
  }
  
  scope :active, -> { where('starts_at <= ? AND ends_at >= ?', Time.current, Time.current) }
  scope :upcoming, -> { where('starts_at > ?', Time.current) }
  scope :expired, -> { where('ends_at < ?', Time.current) }
  
  def active?
    starts_at <= Time.current && ends_at >= Time.current
  end
  
  def redeemed_count
    promotion_redemptions.count
  end
end
