class Order < ApplicationRecord
  include TenantScoped

  belongs_to :tenant_customer
  belongs_to :shipping_method, optional: true
  belongs_to :tax_rate, optional: true
  belongs_to :booking, optional: true
  has_many :line_items, as: :lineable, dependent: :destroy, foreign_key: :lineable_id
  has_many :stock_reservations
  has_one :invoice

  # Statuses:
  #   pending_payment → Customer must pay (initial state)
  #   paid            → Payment completed, ready for fulfillment
  #   cancelled       → Payment timeout or manual cancellation
  #   shipped         → Product sent to customer
  #   refunded        → Order funds sent back to customer
  #   processing      → Paid, but service not yet completed
  #   business_deleted → Business was deleted, order orphaned
  enum :status, {
    pending_payment: 'pending_payment',
    paid:            'paid',
    cancelled:       'cancelled',
    shipped:         'shipped',
    refunded:        'refunded',
    processing:      'processing',
    business_deleted: 'business_deleted'
  }, prefix: true

  enum :order_type, { product: 0, service: 1, mixed: 2 }, prefix: true

  validates :tenant_customer, presence: true
  validates :status, presence: true, inclusion: { in: statuses.keys.map(&:to_s) }
  validates :total_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :tax_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :shipping_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :order_number, presence: true, uniqueness: { scope: :business_id }
  validate :line_items_match_order_type

  before_validation :set_order_number, on: :create
  before_validation :calculate_totals
  before_save :calculate_totals!
  before_destroy :orphan_invoice

  accepts_nested_attributes_for :line_items, allow_destroy: true
  accepts_nested_attributes_for :tenant_customer

  scope :products, -> { where(order_type: order_types[:product]) }
  scope :services, -> { where(order_type: order_types[:service]) }
  scope :mixed, -> { where(order_type: order_types[:mixed]) }
  scope :invoices, -> { where.not(order_type: order_types[:product]) }

  # --- Add Ransack methods --- 
  def self.ransackable_attributes(auth_object = nil)
    %w[id order_number status total_amount tax_amount shipping_amount shipping_address billing_address notes tenant_customer_id shipping_method_id tax_rate_id business_id created_at updated_at order_type]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[business tenant_customer shipping_method tax_rate line_items]
  end

  # Enable Ransack to use enum predicates for order_type
  def self.ransortable_attributes(auth_object = nil)
    ransackable_attributes(auth_object)
  end

  ransacker :order_type, formatter: proc { |v| order_types[v] } do |parent|
    parent.table[:order_type]
  end

  # Determine if payment is required for this order
  def payment_required?
    # Products always require payment
    # Mixed orders follow service rules UNLESS they contain experience services
    order_type_product? || has_experience_services?
  end

  # Check if any line items are experience-type services
  def has_experience_services?
    line_items.any? do |item|
      service = item.service rescue nil
      service&.experience?
    end
  end

  # Check if order contains both products and services
  def is_mixed_order?
    has_products = line_items.any?(&:product?)
    has_services = line_items.any?(&:service?)
    has_products && has_services
  end

  # Get product line items only
  def product_line_items
    line_items.select(&:product?)
  end

  # Get service line items only  
  def service_line_items
    line_items.select(&:service?)
  end

  # Mark order as business deleted and remove associations
  def mark_business_deleted!
    ActsAsTenant.without_tenant do
      update!(
        status: :business_deleted,
        business_id: nil,
        shipping_method_id: nil,
        tax_rate_id: nil
      )
      # Also orphan the associated invoice
      invoice&.mark_business_deleted!
    end
  end

  def set_order_number
    return if order_number.present?
    
    loop do
      self.order_number = "ORD-#{SecureRandom.hex(6).upcase}"
      break unless self.class.exists?(business_id: self.business_id, order_number: self.order_number)
    end
  end

  def calculate_totals
    # Sum totals on in-memory line_items, including nested ones, excluding those marked for destruction
    items = line_items.reject(&:marked_for_destruction?)
    items_total = items.sum { |item| item.total_amount.to_f }
    current_shipping_amount = shipping_method&.cost || 0
    self.shipping_amount = current_shipping_amount if shipping_amount.nil?
    current_tax_amount = 0
    if tax_rate.present?
      taxable_amount = items_total
      taxable_amount += current_shipping_amount if tax_rate.applies_to_shipping?
      current_tax_amount = tax_rate.calculate_tax(taxable_amount)
    end
    self.tax_amount = current_tax_amount if tax_amount.nil?
    current_total_amount = items_total + current_shipping_amount + current_tax_amount
    self.total_amount = current_total_amount if total_amount.nil?
  end

  def calculate_totals!
    # Sum totals on in-memory line_items, excluding those marked for destruction
    items = line_items.reject(&:marked_for_destruction?)
    items_total = items.sum { |item| item.total_amount.to_f }
    current_shipping_amount = shipping_method&.cost || 0
    self.shipping_amount = current_shipping_amount
    current_tax_amount = 0
    if tax_rate.present?
      taxable_amount = items_total
      taxable_amount += current_shipping_amount if tax_rate.applies_to_shipping?
      current_tax_amount = tax_rate.calculate_tax(taxable_amount)
    end
    self.tax_amount = current_tax_amount
    current_total_amount = items_total + current_shipping_amount + current_tax_amount
    self.total_amount = current_total_amount
  end

  def line_items_match_order_type
    return true if new_record?
    # Filter out any line items marked for destruction
    items = line_items.reject(&:marked_for_destruction?)
    return true if items.empty?

    case order_type
    when 'product'
      # Ensure no service items are present
      if items.any?(&:service?)
        errors.add(:base, 'Product orders can only contain product line items')
      end
    when 'service'
      # Ensure no product items are present
      if items.any?(&:product?)
        errors.add(:base, 'Service orders can only contain service line items')
      end
    when 'mixed'
      # Mixed orders can contain both, no validation needed
    end
  end

  def orphan_invoice
    # Mark the associated invoice as business deleted if it exists
    ActsAsTenant.without_tenant do
      invoice&.mark_business_deleted!
    end
  end

end