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
  validates :stock_quantity, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :price_modifier, numericality: true, allow_nil: true # Can be positive or negative

  # Add reserved_quantity field
  attribute :reserved_quantity, :integer, default: 0

  # Basic stock check
  def in_stock?(requested_quantity = 1)
    stock_quantity >= requested_quantity
  end

  # Increment stock level
  def increment_stock!(quantity = 1)
    # Consider using optimistic locking if high concurrency is expected
    self.stock_quantity += quantity
    save!
  end

  # Decrement stock level
  # Returns true if successful, false otherwise
  def decrement_stock!(quantity = 1)
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
    # Update stock and reservation quantities
    increment!(:stock_quantity, reservation.quantity)
    decrement!(:reserved_quantity, reservation.quantity) 
    
    # Delete reservation
    reservation.destroy!
  end
end 