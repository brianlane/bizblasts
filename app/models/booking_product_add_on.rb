class BookingProductAddOn < ApplicationRecord
  belongs_to :booking
  belongs_to :product_variant

  validates :booking, :product_variant, :quantity, :price, :total_amount, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 } # Allow 0 for potential removal via update
  validates :price, :total_amount, numericality: { greater_than_or_equal_to: 0 }
  validate :variant_in_stock, on: :create
  validate :variant_in_stock_for_update, on: :update, if: :quantity_changed?

  before_validation :set_price_and_total # Runs on create and update if price/quantity could change

  # Stock Management Callbacks
  after_create :decrement_variant_stock_on_create
  after_destroy :increment_variant_stock_on_destroy

  before_update :store_original_quantity, if: :quantity_changed?
  after_update :adjust_stock_on_update, if: :quantity_changed?

  attr_accessor :original_quantity # To store quantity before update

  private

  def set_price_and_total
    if product_variant && quantity.to_i >= 0 # quantity can be 0 if about to be rejected_if
      self.price = product_variant.final_price # Always reset price from variant on changes
      self.total_amount = (price.to_d * quantity.to_i).round(2)
    else
      self.price ||= 0
      self.total_amount ||= 0
    end
  end

  def variant_in_stock
    return unless product_variant && quantity.to_i > 0
    return if product_variant.business&.stock_management_disabled?
    unless product_variant.in_stock?(quantity)
      errors.add(:quantity, "for #{product_variant.name} is not sufficient. Only #{product_variant.stock_quantity} available.")
    end
  end
  
  def variant_in_stock_for_update
    return unless product_variant && quantity.to_i > 0 && @original_quantity.present?
    return if product_variant.business&.stock_management_disabled?
    quantity_diff = quantity.to_i - @original_quantity.to_i
    if quantity_diff > 0 # If increasing quantity
      # Check if there is enough stock for the additional quantity requested
      # The current stock_quantity does not yet reflect the release of @original_quantity
      # So we check against stock_quantity for the *additional* amount needed.
      # Consider the available stock as (current_on_hand_stock + @original_quantity) >= new_quantity
      # OR, simpler: current_on_hand_stock >= quantity_diff
      unless product_variant.in_stock?(quantity_diff)
        errors.add(:quantity, "increase for #{product_variant.name} not possible. Only #{product_variant.stock_quantity} additional available.")
      end
    end
  end

  def store_original_quantity
    @original_quantity = self.quantity_was
  end

  def adjust_stock_on_update
    return unless product_variant && @original_quantity.present?
    return if product_variant.business&.stock_management_disabled?
    quantity_diff = quantity.to_i - @original_quantity.to_i

    if quantity_diff > 0 # Quantity increased, so decrement stock further
      product_variant.decrement_stock!(quantity_diff)
    elsif quantity_diff < 0 # Quantity decreased, so increment stock
      product_variant.increment_stock!(-quantity_diff) # -quantity_diff will be positive
    end
  rescue ActiveRecord::RecordInvalid => e
    # If stock adjustment fails (e.g. decrement_stock! raises due to insufficient stock after all)
    # add error to base and consider how to handle this -- an earlier validation should prevent it.
    errors.add(:base, "Stock adjustment failed for #{product_variant.name}: #{e.message}")
    # It might be too late to prevent the save here, depends on AR transaction handling for callbacks.
  end

  def decrement_variant_stock_on_create
    return unless product_variant && quantity.to_i > 0
    return if product_variant.business&.stock_management_disabled?
    unless product_variant.decrement_stock!(quantity)
      errors.add(:base, "Failed to decrement stock for #{product_variant.name}. Operation rolled back.")
      raise ActiveRecord::Rollback
    end
  end

  def increment_variant_stock_on_destroy
    return unless product_variant && quantity.to_i > 0
    return if product_variant.business&.stock_management_disabled?
    # quantity here is the quantity at the time of destruction
    product_variant.increment_stock!(quantity)
  end
end 