class EstimateItem < ApplicationRecord
  attr_accessor :save_as_service, :service_type, :service_name,
                :save_as_product, :product_type, :product_name
  belongs_to :estimate
  belongs_to :service, optional: true
  belongs_to :product, optional: true
  belongs_to :product_variant, optional: true

  has_one_attached :image # For displaying product/service images in PDF

  enum :item_type, { service: 0, product: 1, labor: 2, part: 3 }

  # Validations - context aware
  validates :qty, numericality: { only_integer: true, greater_than: 0 }
  validates :cost_rate, :total, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :tax_rate, numericality: { greater_than_or_equal_to: 0, allow_nil: true }

  # Type-specific validations
  # Note: service_id and product_id are optional even for their types
  # This allows custom descriptions without selecting an existing service/product
  validates :hours, :hourly_rate, presence: true, numericality: { greater_than: 0 }, if: :labor?
  validates :description, presence: true

  # Prevent duplicate items within the same estimate
  validate :no_duplicate_items

  before_validation :set_defaults, :sync_from_associations, :calculate_total
  after_initialize :set_item_type_from_associations

  scope :required, -> { where(optional: false) }
  scope :optional_items, -> { where(optional: true) }
  scope :customer_selected, -> { where(customer_selected: true, customer_declined: false) }
  scope :customer_declined, -> { where(customer_declined: true) }
  scope :included_in_totals, -> { where(customer_declined: false).where("optional = false OR customer_selected = true") }
  scope :by_position, -> { order(:position) }

  # Returns the tax amount for this line item (rate * qty * tax_rate%)
  # Only calculates if item is selected and not declined
  def tax_amount
    return 0 if customer_declined? || (optional? && !customer_selected?)
    base_amount = labor? ? (hours.to_d * hourly_rate.to_d) : (qty.to_i * cost_rate.to_d)
    (base_amount) * (tax_rate.to_d / 100.0)
  end

  def total_with_tax
    total.to_d + tax_amount
  end

  # Display name for line item
  def display_name
    case item_type&.to_sym
    when :service
      service&.name || description
    when :product
      product_variant&.full_name || product&.name || description
    when :labor
      "Labor: #{description}"
    when :part
      "Part: #{description}"
    else
      description
    end
  end

  # Get image for PDF display
  def display_image
    case item_type&.to_sym
    when :service
      service&.primary_image if service&.respond_to?(:primary_image)
    when :product
      product&.primary_image if product&.respond_to?(:primary_image)
    else
      image if image.attached?
    end
  end

  # Check if this item should be included in totals
  def included_in_totals?
    !customer_declined? && (!optional? || customer_selected?)
  end

  # Get the effective total (0 if excluded from totals)
  def effective_total
    included_in_totals? ? total.to_d : 0
  end

  # Get the effective tax (0 if excluded from totals)
  def effective_tax
    included_in_totals? ? tax_amount : 0
  end

  private

  def calculate_total
    if labor?
      self.total = (hours.to_d * hourly_rate.to_d)
    else
      self.total = qty.to_i * cost_rate.to_d
    end
  end

  def set_defaults
    self.tax_rate ||= 0.0
    self.position ||= estimate&.estimate_items&.maximum(:position).to_i + 1
    self.customer_selected = true if customer_selected.nil?
    self.customer_declined = false if customer_declined.nil?
  end

  def sync_from_associations
    # Auto-populate from service
    if service.present? && cost_rate.blank?
      self.cost_rate = service.base_price if service.respond_to?(:base_price)
      self.cost_rate ||= service.price if service.respond_to?(:price)
      self.description ||= service.description
    end

    # Auto-populate from product/variant
    if product_variant.present? && cost_rate.blank?
      self.cost_rate = product_variant.final_price if product_variant.respond_to?(:final_price)
      self.cost_rate ||= product_variant.price if product_variant.respond_to?(:price)
      self.description ||= product_variant.product.description if product_variant.product.present?
    elsif product.present? && cost_rate.blank?
      self.cost_rate = product.price
      self.description ||= product.description
    end

    # For labor, calculate cost_rate from hourly_rate * hours for display purposes
    if labor? && hourly_rate.present? && hours.present?
      self.cost_rate = hourly_rate
      self.qty ||= hours.ceil.clamp(1, Float::INFINITY) # Round up hours to whole number for qty, minimum 1
    end
  end

  def set_item_type_from_associations
    return if item_type.present?
    return unless new_record?

    if service_id.present?
      self.item_type = :service
    elsif product_id.present?
      self.item_type = :product
    end
  end

  def no_duplicate_items
    return unless estimate.present?

    # Find duplicate items in the same estimate (excluding self if persisted)
    duplicates = estimate.estimate_items.where.not(id: id)

    case item_type&.to_sym
    when :service
      # Check for duplicate service_id if present
      if service_id.present?
        if duplicates.where(item_type: :service, service_id: service_id).exists?
          errors.add(:base, "This service has already been added to the estimate")
        end
      end
    when :product
      # Check for duplicate product_id (and variant if present)
      if product_id.present?
        scope = duplicates.where(item_type: :product, product_id: product_id)
        scope = scope.where(product_variant_id: product_variant_id) if product_variant_id.present?
        if scope.exists?
          errors.add(:base, "This product has already been added to the estimate")
        end
      end
    # Labor and part items can have duplicates since they're custom
    end
  end
end
