# frozen_string_literal: true

class Promotion < ApplicationRecord
  include TenantScoped
  
  has_many :promotion_redemptions, dependent: :destroy
  has_many :customers, through: :promotion_redemptions
  
  # Product and Service associations for targeted promotions
  has_many :promotion_products, dependent: :destroy
  has_many :products, through: :promotion_products
  has_many :promotion_services, dependent: :destroy
  has_many :services, through: :promotion_services
  
  validates :name, presence: true
  validates :code, uniqueness: { scope: :business_id }, allow_blank: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validates :discount_type, presence: true
  validates :discount_value, presence: true, numericality: { greater_than: 0 }
  validates :active, inclusion: { in: [true, false] }
  validates :current_usage, numericality: { greater_than_or_equal_to: 0 }
  validates :usage_limit, numericality: { greater_than: 0 }, allow_nil: true
  
  # Business rule: Code-based promotions cannot allow discount code stacking
  validate :code_based_promotions_cannot_allow_discount_codes
  before_save :enforce_stacking_rules
  
  enum :discount_type, {
    percentage: 0,
    fixed_amount: 1
  }
  
  scope :active, -> { where(active: true).where('start_date <= ? AND end_date >= ?', Time.current, Time.current) }
  scope :upcoming, -> { where(active: true).where('start_date > ?', Time.current) }
  scope :expired, -> { where(active: false).or(where('end_date < ?', Time.current)) }
  scope :current, -> { active } # Alias for currently active promotions
  scope :automatic, -> { where(code: [nil, '']) } # Promotions that apply automatically
  scope :code_based, -> { where.not(code: [nil, '']) } # Promotions that require codes
  
  def single_use?
    usage_limit == 1
  end
  
  def automatic_promotion?
    code.blank?
  end
  
  def code_based_promotion?
    code.present?
  end
  
  def applies_to_all_products?
    applicable_to_products? && promotion_products.empty?
  end
  
  def applies_to_all_services?
    applicable_to_services? && promotion_services.empty?
  end
  
  def applies_to_specific_products?
    applicable_to_products? && promotion_products.any?
  end
  
  def applies_to_specific_services?
    applicable_to_services? && promotion_services.any?
  end
  
  def applies_to_product?(product)
    return false unless applicable_to_products?
    return true if applies_to_all_products?
    promotion_products.exists?(product: product)
  end
  
  def applies_to_service?(service)
    return false unless applicable_to_services?
    return true if applies_to_all_services?
    promotion_services.exists?(service: service)
  end
  
  def allows_discount_codes_on_promotion?
    allow_discount_codes?
  end
  
  def usage_limit_reached?
    usage_limit.present? && current_usage >= usage_limit
  end
  
  # Check if promotion is currently active (within date range, active flag, and not usage limited)
  def currently_active?
    active? && 
    start_date <= Time.current && 
    end_date >= Time.current && 
    !usage_limit_reached?
  end

  # Calculate the discount amount based on promotion type and original amount
  def calculate_discount(original_amount)
    return 0 unless currently_active? && original_amount.to_f > 0
    
    if percentage?
      (original_amount * (discount_value / 100.0)).round(2)
    elsif fixed_amount?
      [discount_value, original_amount].min # Don't discount more than the original amount
    else
      0
    end
  end
  
  # Calculate the promotional price (original price minus discount)
  def calculate_promotional_price(original_price)
    return original_price unless currently_active?
    
    discount_amount = calculate_discount(original_price)
    (original_price - discount_amount).round(2)
  end
  
  # Get promotional display text for UI
  def display_text
    return nil unless currently_active?
    
    case discount_type
    when 'percentage'
      "#{discount_value.to_i}% OFF"
    when 'fixed_amount'
      "$#{discount_value} OFF"
    end
  end
  
  # Class method to find active automatic promotion for a specific product
  def self.active_promotion_for_product(product)
    return nil unless product
    
    # Only look for automatic promotions (no code required)
    # First check specific product promotions
    specific_promotion = automatic.joins(:promotion_products)
                        .where(promotion_products: { product: product })
                        .where(applicable_to_products: true)
                        .find { |p| p.currently_active? }
    
    return specific_promotion if specific_promotion
    
    # Then check promotions that apply to all products
    all_products_promotion = automatic.where(applicable_to_products: true)
                            .where.not(id: PromotionProduct.select(:promotion_id))
                            .find { |p| p.currently_active? }
    
    all_products_promotion
  end
  
  # Class method to find active automatic promotion for a specific service
  def self.active_promotion_for_service(service)
    return nil unless service
    
    # Only look for automatic promotions (no code required)
    # First check specific service promotions
    specific_promotion = automatic.joins(:promotion_services)
                        .where(promotion_services: { service: service })
                        .where(applicable_to_services: true)
                        .find { |p| p.currently_active? }
    
    return specific_promotion if specific_promotion
    
    # Then check promotions that apply to all services
    all_services_promotion = automatic.where(applicable_to_services: true)
                            .where.not(id: PromotionService.select(:promotion_id))
                            .find { |p| p.currently_active? }
    
    all_services_promotion
  end

  # Allow searching/filtering on these attributes in ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id name code description discount_type discount_value start_date end_date usage_limit current_usage active business_id created_at updated_at]
  end

  # Allow searching/filtering through these associations in ActiveAdmin
  def self.ransackable_associations(auth_object = nil)
    %w[business promotion_redemptions customers products services promotion_products promotion_services]
  end

  private

  def code_based_promotions_cannot_allow_discount_codes
    if code_based_promotion? && allow_discount_codes?
      errors.add(:allow_discount_codes, "cannot be enabled for code-based promotions. Only automatic promotions can stack with discount codes.")
    end
  end

  def enforce_stacking_rules
    # Automatically disable stacking for code-based promotions
    if code_based_promotion?
      self.allow_discount_codes = false
    end
  end
end
