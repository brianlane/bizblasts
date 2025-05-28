class LineItem < ApplicationRecord
  # Allow nested creation of line items without requiring parent until persist
  belongs_to :lineable, polymorphic: true, optional: true
  # Ensure lineable exists on update (after creation)
  validates :lineable, presence: true, on: :update

  # New associations for service line items
  belongs_to :service, optional: true
  belongs_to :staff_member, optional: true

  # Validate that each line item references exactly one of product_variant or service
  validate :product_or_service_presence

  belongs_to :product_variant, optional: true

  # Delegate business_id for validation purposes
  # Ensure lineable is set before validation runs
  delegate :business_id, to: :lineable, allow_nil: true

  validates :product_variant, presence: true, if: :product?
  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Security Validation: Ensure product belongs to the same business as the order/invoice
  validate :business_consistency
  validate :stock_sufficiency, if: :product?

  # Set price from variant and calculate total before validation on creation
  before_validation :set_price_and_total, on: :create
  # Update total if quantity changes after creation
  before_save       :update_total_amount,  if: :will_save_change_to_quantity?
  after_save        :update_parent_totals

  scope :products, -> { where(lineable_type: 'ProductVariant') }
  scope :services, -> { where(lineable_type: 'Service') }

  validates :service, presence: true, if: :service?, unless: :orphaned_line_item?
  validates :staff_member, presence: true, if: :service?, unless: :orphaned_line_item?

  def product?
    # A line item is a product if it has no service_id
    service_id.blank?
  end

  def service?
    # A line item is a service if it has a service_id
    service_id.present?
  end

  def orphaned_line_item?
    # Line item is orphaned if it was a service line item but service was deleted
    service_id.nil? && staff_member_id.present?
  end

  # --- Add Ransack methods --- 
  def self.ransackable_attributes(auth_object = nil)
    %w[id lineable_type lineable_id product_variant_id quantity price total_amount created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[lineable product_variant]
  end
  # --- End Ransack methods ---

  private

  def set_price_and_total
    # Auto-set price and total for products and services
    return unless quantity.present?
    if product_variant.present?
      self.price        ||= product_variant.final_price
      self.total_amount = (price * quantity).round(2)
    elsif service.present?
      # Use service price for service line items
      self.price        ||= service.price
      self.total_amount = (price * quantity).round(2)
    end
  end

  def update_total_amount
    self.total_amount = (price * quantity).round(2)
  end

  def update_parent_totals
    if (parent = lineable) && parent.respond_to?(:calculate_totals)
      # Let the parent's own before_save :calculate_totals handle it.
      parent.save(validate: false) 
    end
  end

  def business_consistency
    return unless product_variant && lineable

    # Check if product_variant is loaded and has a product, which has a business_id
    product_business_id = product_variant.product&.business_id
    # Check if lineable is loaded and has a business_id
    lineable_business_id = lineable.business_id

    if product_business_id != lineable_business_id
      errors.add(:product_variant, "must belong to the same business as the #{lineable_type.downcase}")
    end
  end

  def product_or_service_presence
    # Allow orphaned line items (service was deleted but staff_member_id remains)
    return if orphaned_line_item?
    
    if product_variant_id.blank? && service_id.blank?
      errors.add(:base, 'Line items must have either a product or a service selected')
    elsif product_variant_id.present? && service_id.present?
      errors.add(:base, 'Line items cannot have both product and service selected')
    elsif service_id.present? && staff_member_id.blank?
      errors.add(:staff_member, 'must be selected for service line items')
    end
  end

  # Validate that product line items do not exceed available stock
  def stock_sufficiency
    return unless quantity.present? && product_variant.present?

    unless product_variant.in_stock?(quantity)
      errors.add(:quantity, "for #{product_variant.name} is not sufficient. Only #{product_variant.stock_quantity} available.")
    end
  end
end 