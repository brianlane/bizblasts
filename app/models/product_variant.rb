# app/models/product_variant.rb
class ProductVariant < ApplicationRecord
  belongs_to :product
  has_many :line_items, dependent: :destroy

  # Ensure variant is scoped to the same business as the product
  # This relies on the product association being present and valid
  delegate :business, :business_id, to: :product, allow_nil: true

  validates :name, presence: true # E.g., "Large, Red"
  validates :stock_quantity, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :price_modifier, numericality: true, allow_nil: true # Can be positive or negative

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
end 