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
  validate :price_modifier_not_nan
  validate :final_price_not_negative
  validate :price_modifier_format_valid
  
  # Custom setter to parse numbers from strings with non-numeric characters
  def price_modifier=(value)
    if value.is_a?(String) && value.present?
      # Extract valid decimal number with optional minus sign
      # Handles: "-5.50", "5.50", "-$5.50", "$-5.50", "$10", "5", "-5"

      # Determine negativity only if the minus sign is actually indicating a negative value.
      # Consider strings that may include hyphens not related to negativity (e.g., "555-1234").
      # Treat the value as negative when the first non-whitespace character is '-' OR
      # when a currency symbol ('$') is immediately followed by '-'.
      stripped = value.strip
      is_negative = stripped.start_with?('-') || stripped.start_with?('$-')
      # Extract the numeric part (digits with optional decimal)
      number_match = value.match(/(\d+(?:\.\d{1,2})?)/)

      if number_match
        parsed_float = number_match[1].to_f.round(2)
        parsed_float = -parsed_float if is_negative
        @invalid_price_modifier_input = nil # Clear any previous invalid input
        super(parsed_float)
      else
        # Store the invalid input for validation
        @invalid_price_modifier_input = value
        super(nil)
      end
    elsif value.nil?
      # Allow nil to be set for presence validation
      @invalid_price_modifier_input = nil # Clear any previous invalid input
      super(nil)
    else
      @invalid_price_modifier_input = nil # Clear any previous invalid input
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

  private

  def price_modifier_not_nan
    return unless price_modifier.present?
    
    if price_modifier.is_a?(Float) && price_modifier.nan?
      errors.add(:price_modifier, "cannot be NaN")
    end
  end

  def final_price_not_negative
    return unless product&.price.present? && price_modifier.present?
    
    calculated_final_price = final_price
    if calculated_final_price < 0
      base_price = product.price
      errors.add(:price_modifier, "cannot make the final price negative (base price: $#{base_price}, modifier: $#{price_modifier}, final: $#{calculated_final_price.round(2)})")
    end
  end

  def price_modifier_format_valid
    return unless @invalid_price_modifier_input
    
    errors.add(:price_modifier, "must be a valid number (e.g., '5.50', '-5.50', or '$5.50')")
  end
end