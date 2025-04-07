class Promotion < ApplicationRecord
  include TenantScoped
  
  has_many :promotion_redemptions, dependent: :destroy
  has_many :customers, through: :promotion_redemptions
  
  validates :name, presence: true
  validates :code, presence: true, uniqueness: { scope: :business_id }
  validates :start_date, presence: true
  validates :end_date, presence: true
  validates :discount_type, presence: true
  validates :discount_value, presence: true, numericality: { greater_than: 0 }
  validates :active, inclusion: { in: [true, false] }
  validates :current_usage, numericality: { greater_than_or_equal_to: 0 }
  validates :usage_limit, numericality: { greater_than: 0 }, allow_nil: true
  
  enum :discount_type, {
    percentage: 0,
    fixed_amount: 1
  }
  
  scope :active, -> { where(active: true).where('start_date <= ? AND end_date >= ?', Time.current, Time.current) }
  scope :upcoming, -> { where(active: true).where('start_date > ?', Time.current) }
  scope :expired, -> { where(active: false).or(where('end_date < ?', Time.current)) }
  
  def single_use?
    usage_limit == 1
  end
  
  def usage_limit_reached?
    usage_limit.present? && current_usage >= usage_limit
  end

  # Allow searching/filtering on these attributes in ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id name code description discount_type discount_value start_date end_date usage_limit current_usage active business_id created_at updated_at]
  end

  # Allow searching/filtering through these associations in ActiveAdmin
  def self.ransackable_associations(auth_object = nil)
    %w[business promotion_redemptions customers]
  end
end
