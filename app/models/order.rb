class Order < ApplicationRecord
  include TenantScoped

  belongs_to :tenant_customer
  belongs_to :shipping_method, optional: true
  belongs_to :tax_rate, optional: true
  belongs_to :booking, optional: true
  has_many :line_items, as: :lineable, dependent: :destroy, foreign_key: :lineable_id
  has_many :stock_reservations

  enum :status, { pending: 'pending', processing: 'processing', shipped: 'shipped', completed: 'completed', cancelled: 'cancelled' }, prefix: true
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
  # --- End Ransack methods ---

  private

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
end