class LineItem < ApplicationRecord
  belongs_to :lineable, polymorphic: true
  validates :lineable, presence: true
  belongs_to :product_variant

  # Delegate business_id for validation purposes
  # Ensure lineable is set before validation runs
  delegate :business_id, to: :lineable, allow_nil: true

  validates :product_variant, presence: true
  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Security Validation: Ensure product belongs to the same business as the order/invoice
  validate :business_consistency

  # Set price from variant and calculate total before validation on creation
  before_validation :set_price_and_total, on: :create
  # Update total if quantity changes after creation
  before_save       :update_total_amount,  if: :will_save_change_to_quantity?
  after_save        :update_parent_totals

  scope :products, -> { where(lineable_type: 'ProductVariant') }
  scope :services, -> { where(lineable_type: 'Service') }

  def product?
    # The line item belongs to a product if the lineable is an Order with order_type product or mixed
    if lineable.is_a?(Order)
      lineable.order_type_product? || lineable.order_type_mixed?
    else
      # Default to previous implementation
      lineable_type == 'ProductVariant'
    end
  end

  def service?
    # The line item belongs to a service if the lineable is an Order with order_type service or mixed
    if lineable.is_a?(Order)
      lineable.order_type_service? || lineable.order_type_mixed?
    else
      # Default to previous implementation
      lineable_type == 'Service'
    end
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
    return unless product_variant.present? && quantity.present?
    self.price        ||= product_variant.final_price
    self.total_amount = (price * quantity).round(2)
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
end 