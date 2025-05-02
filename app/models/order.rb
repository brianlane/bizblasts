class Order < ApplicationRecord
  include TenantScoped

  belongs_to :tenant_customer
  belongs_to :shipping_method, optional: true
  belongs_to :tax_rate, optional: true
  has_many :line_items, as: :lineable, dependent: :destroy, foreign_key: :lineable_id

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
  before_save :calculate_totals

  accepts_nested_attributes_for :line_items, allow_destroy: true

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
    line_items.reload # Ensure association is fresh
    # Calculate actual value from database records
    items_total = line_items.sum { |item| item.total_amount.to_f }

    # Set shipping amount
    current_shipping_amount = shipping_method&.cost || 0
    self.shipping_amount = current_shipping_amount
    
    # Calculate tax amount
    current_tax_amount = 0
    if tax_rate.present?
      taxable_amount = items_total
      taxable_amount += current_shipping_amount if tax_rate.applies_to_shipping?
      current_tax_amount = tax_rate.calculate_tax(taxable_amount)
    end
    self.tax_amount = current_tax_amount
    
    # Calculate total amount
    current_total_amount = items_total + current_shipping_amount + current_tax_amount
    self.total_amount = current_total_amount
  end

  def line_items_match_order_type
    return true if line_items.empty? # Skip validation if no line items yet

    case order_type
    when 'product'
      # For product orders, all line items must be directly linked to this order
      # Check if any line item has a service lineable_type
      has_service_line_items = ActiveRecord::Base.connection.execute(
        "SELECT COUNT(*) FROM line_items WHERE lineable_id = #{id} AND lineable_type = 'Service'"
      ).first["count"].to_i > 0
      
      errors.add(:base, 'Product orders can only contain product line items') if has_service_line_items
    when 'service'  
      # For service orders, all line items must be service line items
      # Check if any line item has an Order lineable_type
      has_order_line_items = line_items.where("lineable_type != 'Service'").exists?
      
      errors.add(:base, 'Service orders can only contain service line items') if has_order_line_items
    when 'mixed'
      # Mixed orders can contain both, no validation needed
    end
  end
end