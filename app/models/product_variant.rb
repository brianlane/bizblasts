# app/models/product_variant.rb
class ProductVariant < ApplicationRecord
  belongs_to :product
  has_many :line_items, dependent: :destroy
  has_many :stock_reservations
  has_many :booking_product_add_ons, dependent: :destroy

  # Ensure variant is scoped to the same business as the product
  # This relies on the product association being present and valid
  delegate :business, :business_id, to: :product, allow_nil: true

  validates :name, presence: true # E.g., "Large, Red"
  validates :stock_quantity, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, unless: -> { business&.stock_management_disabled? }
  validates :price_modifier, numericality: true, allow_nil: true # Can be positive or negative
  
  # Custom setter to parse numbers from strings with non-numeric characters
  def price_modifier=(value)
    if value.is_a?(String)
      # Extract numbers, decimal point, and minus sign (e.g., "-$5.50" -> "-5.50", "+$10" -> "10")
      parsed_value = value.gsub(/[^\d\.\-]/, '')
      # Convert to float then round to 2 decimal places for currency
      if parsed_value.present?
        parsed_float = parsed_value.to_f.round(2)
        super(parsed_float)
      else
        super(nil)
      end
    else
      super(value)
    end
  end

  # Add reserved_quantity field
  attribute :reserved_quantity, :integer, default: 0

  # Basic stock check
  def in_stock?(requested_quantity = 1)
    return true if business&.stock_management_disabled?
    stock_quantity >= requested_quantity
  end

  # Increment stock level
  def increment_stock!(quantity = 1)
    return true if business&.stock_management_disabled?
    # Consider using optimistic locking if high concurrency is expected
    self.stock_quantity += quantity
    save!
  end

  # Decrement stock level
  # Returns true if successful, false otherwise
  def decrement_stock!(quantity = 1)
    return true if business&.stock_management_disabled?
    
    raise "Cannot decrement below 0" if stock_quantity - quantity < 0
    
    with_lock do
      self.stock_quantity -= quantity
      save!
    end
    true
  rescue
    errors.add(:stock_quantity, "is insufficient to decrement by #{quantity}")
    false  
  end

  # Calculate the final price for this variant
  def final_price
    base_price = product&.price || 0
    modifier = price_modifier || 0
    (base_price + modifier).round(2)
  end

  # Subscription pricing methods
  def subscription_price
    return final_price unless product&.subscription_enabled?
    final_price - subscription_discount_amount
  end
  
  def subscription_discount_amount
    return 0 unless product&.subscription_enabled? || product&.business&.subscription_discount_percentage.blank?
    (final_price * (product.business.subscription_discount_percentage / 100.0)).round(2)
  end
  
  def subscription_savings_percentage
    return 0 if final_price.zero? || !product&.subscription_enabled?
    ((subscription_discount_amount / final_price) * 100).round
  end
  
  def can_be_subscribed?
    product&.active? && product&.subscription_enabled? && in_stock?(1)
  end
  
  def subscription_display_price
    product&.subscription_enabled? ? subscription_price : final_price
  end

  # --- Add Ransack methods --- 
  def self.ransackable_attributes(auth_object = nil)
    # Allowlist attributes for searching/filtering in ActiveAdmin
    %w[id product_id name price_modifier stock_quantity created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    # Allowlist associations for searching/filtering in ActiveAdmin
    %w[product line_items]
  end
  # --- End Ransack methods ---

  def reserve_stock!(quantity, order)
    return true if business&.stock_management_disabled?
    
    # Check available stock
    if stock_quantity - reserved_quantity >= quantity
      # Create reservation
      stock_reservations.create!(
        order: order, 
        quantity: quantity,
        expires_at: 15.minutes.from_now
      )
      
      # Update stock and reservation quantities
      decrement!(:stock_quantity, quantity) 
      increment!(:reserved_quantity, quantity)
      
      true
    else
      false
    end
  end
  
  def release_reservation!(reservation)
    if business&.stock_management_enabled?
      # Update stock and reservation quantities
      increment!(:stock_quantity, reservation.quantity)
      decrement!(:reserved_quantity, reservation.quantity) 
    end
    
    # Delete reservation
    reservation.destroy!
  end
end