class DiscountCode < ApplicationRecord
  include TenantScoped
  
  belongs_to :business
  belongs_to :generated_by_referral, class_name: 'Referral', optional: true
  belongs_to :used_by_customer, class_name: 'TenantCustomer', optional: true
  belongs_to :tenant_customer, class_name: 'TenantCustomer', optional: true
  
  validates :code, presence: true, uniqueness: { scope: :business_id }
  validates :discount_type, presence: true, inclusion: { in: %w[percentage fixed_amount] }
  validates :discount_value, presence: true, numericality: { greater_than: 0 }
  validates :active, inclusion: { in: [true, false] }
  validates :usage_count, numericality: { greater_than_or_equal_to: 0 }
  validates :max_usage, numericality: { greater_than: 0 }, allow_nil: true
  
  scope :active, -> { where(active: true) }
  scope :expired, -> { where('expires_at < ?', Time.current) }
  scope :valid, -> { active.where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :single_use, -> { where(single_use: true) }
  scope :multi_use, -> { where(single_use: false) }
  scope :referral_generated, -> { where.not(generated_by_referral_id: nil) }
  scope :manual, -> { where(generated_by_referral_id: nil) }
  
  def expired?
    expires_at.present? && expires_at < Time.current
  end
  
  def valid_for_use?
    active? && !expired? && !usage_limit_reached?
  end
  
  def usage_limit_reached?
    max_usage.present? && usage_count >= max_usage
  end
  
  def can_be_used_by?(customer)
    return false unless valid_for_use?
    return false if single_use? && used_by_customer.present? && used_by_customer != customer
    true
  end
  
  def calculate_discount(original_amount)
    return 0 unless valid_for_use? && original_amount.to_f > 0
    
    case discount_type
    when 'percentage'
      (original_amount * (discount_value / 100.0)).round(2)
    when 'fixed_amount'
      [discount_value, original_amount].min
    else
      0
    end
  end
  
  def mark_used!(customer)
    increment!(:usage_count)
    update!(used_by_customer: customer) if single_use?
  end
  
  def referral_generated?
    generated_by_referral.present?
  end
  
  def manual_code?
    generated_by_referral.nil?
  end
end 