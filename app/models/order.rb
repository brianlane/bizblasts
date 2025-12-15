class Order < ApplicationRecord
  include TenantScoped

  belongs_to :tenant_customer, optional: true  # Allow nil for orphaned orders
  belongs_to :shipping_method, optional: true
  belongs_to :tax_rate, optional: true
  belongs_to :booking, optional: true
  belongs_to :business, optional: true  # Allow nil for orphaned orders
  belongs_to :customer_subscription, optional: true
  has_many :line_items, as: :lineable, dependent: :destroy, foreign_key: :lineable_id
  has_many :stock_reservations
  has_one :invoice
  
  # Add association for test compatibility (orders can be created from subscriptions)
  has_many :customer_subscriptions, through: :tenant_customer

  # Statuses:
  #   pending_payment → Customer must pay (initial state)
  #   paid            → Payment completed, ready for fulfillment
  #   cancelled       → Payment timeout or manual cancellation
  #   shipped         → Product sent to customer
  #   refunded        → Order funds sent back to customer
  #   processing      → Paid, but service not yet completed
  #   completed       → Service delivered, product shipped, or mixed order fulfilled
  #   business_deleted → Business was deleted, order orphaned
  enum :status, {
    pending_payment: 'pending_payment',
    paid:            'paid',
    cancelled:       'cancelled',
    shipped:         'shipped',
    refunded:        'refunded',
    processing:      'processing',
    completed:       'completed',
    business_deleted: 'business_deleted'
  }, prefix: true

  enum :order_type, { product: 0, service: 1, mixed: 2 }, prefix: true

  validates :tenant_customer, presence: true, unless: :status_business_deleted?
  validates :status, presence: true, inclusion: { in: statuses.keys.map(&:to_s) }
  validates :total_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :tax_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :shipping_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :order_number, presence: true, uniqueness: { scope: :business_id }
  validate :line_items_match_order_type
  
  # Override TenantScoped validation to allow nil business for orphaned orders
  validates :business, presence: true, unless: :status_business_deleted?

  before_validation :set_order_number, on: :create
  before_validation :calculate_totals
  before_save :calculate_totals!
  before_destroy :orphan_invoice
  after_create :create_invoice_for_service_orders
  after_create :send_staggered_emails
  after_update :send_order_status_update_email, if: :saved_change_to_status?

  accepts_nested_attributes_for :line_items, allow_destroy: true
  accepts_nested_attributes_for :tenant_customer
  
  # Virtual attribute for promo code form submission
  attr_accessor :promo_code
  
  # Virtual attribute to skip total calculation (for payment collection orders)
  attr_accessor :skip_total_calculation

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

  # Returns the order's created_at in the business's local timezone (or app Time.zone if business not present)
  def local_created_at
    created_at&.in_time_zone(business&.time_zone.presence || Time.zone)
  end

  # Check if order contains both products and services
  
  # Check if order contains tip-eligible items
  def has_tip_eligible_items?
    line_items.any? { |item| item.tip_eligible? }
  end
  
  # Get tip-eligible items
  def tip_eligible_items
    line_items.select { |item| item.tip_eligible? }
  end

  def tip_enabled?
    has_tip_eligible_items?
  end

  def is_mixed_order?
    has_products = line_items.any?(&:product?)
    has_services = line_items.any?(&:service?)
    has_products && has_services
  end

  # Calculate subtotal (line items total before tax, shipping, and tips)
  def subtotal_amount
    line_items.sum { |item| item.total_amount.to_f }
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
      update_columns(
        status: 'business_deleted',
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
    # Subtract promo discount if present
    current_total_amount -= (promo_discount_amount || 0)
    self.total_amount = current_total_amount if total_amount.nil?
  end

  def calculate_totals!
    # Skip calculation if explicitly requested (for payment collection orders)
    return if skip_total_calculation
    
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
    # Subtract promo discount if present
    current_total_amount -= (promo_discount_amount || 0)
    # Add tip amount if present
    current_total_amount += (tip_amount || 0)
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
    invoice&.mark_business_deleted!
  end

  def send_order_status_update_email
    # Skip email for initial status or business_deleted status
    previous_status = saved_changes['status'][0]
    return if previous_status.nil? || status == 'business_deleted'
    
    begin
      NotificationService.order_status_update(self, previous_status)
      Rails.logger.info "[NOTIFICATION] Sent order status update notification for Order ##{order_number} (#{previous_status} → #{status})"
    rescue => e
      Rails.logger.error "[NOTIFICATION] Failed to send order status update notification for Order ##{order_number}: #{e.message}"
    end
  end

  def send_staggered_emails
    # Skip notifications for business_deleted status
    return if status == 'business_deleted'
    
    begin
      # Use staggered email service to prevent rate limiting
      StaggeredEmailService.deliver_order_emails(self)
      Rails.logger.info "[EMAIL] Scheduled staggered emails for Order ##{order_number}"
    rescue => e
      Rails.logger.error "[EMAIL] Failed to schedule staggered emails for Order ##{order_number}: #{e.message}"
    end
  end

  def create_invoice_for_service_orders
    # Only create invoices for service orders and mixed orders (not product orders)
    # Product orders need payment before shipping, so no invoice needed
    return unless order_type_service? || order_type_mixed?
    
    # Skip if invoice already exists
    return if invoice.present?
    
    # Skip if this order was created through the public customer-facing flow
    # (those orders should handle their own payment/invoice flow)
    # We identify business manager created orders by checking if there are line items with services
    # that are being invoiced after the service is rendered (past service orders)
    
    # Ensure we have required data - be more strict about validation
    return unless tenant_customer.present? && tenant_customer.persisted?
    return unless business.present? && business.persisted?
    
    # Additional safety check - ensure the order itself is valid and persisted
    return unless persisted? && errors.empty?
    
    begin
      # Create the invoice
      new_invoice = build_invoice(
        tenant_customer: tenant_customer,
        business: business,
        due_date: 30.days.from_now, # Default 30 day payment terms
        status: :pending,
        shipping_method: shipping_method,
        tax_rate: tax_rate
      )
      
      # The invoice's calculate_totals method will handle copying amounts from the order
      if new_invoice.save
        Rails.logger.info "[INVOICE] Created invoice #{new_invoice.invoice_number} for order #{order_number}"
      else
        Rails.logger.error "[INVOICE] Failed to create invoice for order #{order_number}: #{new_invoice.errors.full_messages.join(', ')}"
      end
    rescue => e
      Rails.logger.error "[INVOICE] Error creating invoice for order #{order_number}: #{e.message}"
    end
  end

  # Determine if this order is eligible for a refund action in the UI
  def refundable?
    return false if status_refunded? || status_cancelled? || status_business_deleted?
    return false unless invoice
    
    # Must have successful payments that aren't already refunded
    refundable_payments = invoice.payments.successful.where.not(status: :refunded)
    return false unless refundable_payments.exists?
    
    # All payments must have been processed through Stripe (have stripe_payment_intent_id)
    # Manual payments (marked as paid) cannot be refunded through Stripe
    refundable_payments.where.not(stripe_payment_intent_id: nil).count == refundable_payments.count
  end

  # Check if all payments on the associated invoice are refunded and update order status accordingly
  # This method should be called after a payment is refunded to ensure consistent state
  def check_and_update_refund_status!
    return unless invoice
    
    # Only update to refunded if all payments on the invoice are refunded
    if invoice.payments.where.not(status: :refunded).none?
      update!(status: :refunded)
      Rails.logger.info "[ORDER] Updated order ##{order_number} status to refunded - all invoice payments refunded"
    else
      Rails.logger.info "[ORDER] Order ##{order_number} not yet refunded - #{invoice.payments.where.not(status: :refunded).count} payments still pending refund"
    end
  end

  # Check if order should be automatically completed based on business rules
  def should_complete?
    return false if status_completed? || status_cancelled? || status_refunded? || status_business_deleted?
    
    case order_type
    when 'service'
      # Service orders: must be paid/processing
      return false unless status_paid? || status_processing?
      
      # No booking: complete immediately after payment
      return true if booking.nil?
      
      # Has booking: complete only if booking time has passed
      booking_time_passed?
    when 'product'
      # Product orders: must be paid and shipped
      status_paid? && status_shipped?
    when 'mixed'
      # Mixed orders: must be paid, shipped, and booking time passed (if booking exists)
      return false unless status_paid? && status_shipped?
      
      # No booking: complete immediately after shipping
      return true if booking.nil?
      
      # Has booking: complete only if booking time has passed
      booking_time_passed?
    else
      false
    end
  end

  # Check if booking time has passed (start_time + duration or end_time)
  def booking_time_passed?
    return false unless booking
    
    current_time = Time.current
    
    # Prefer booking.end_time; if it's absent we cannot reliably determine.
    end_time = booking.end_time
    return false unless end_time.present?
    
    current_time >= end_time
  end

  # Complete the order if it should be completed
  def complete_if_ready!
    return false unless should_complete?
    
    update!(status: :completed)
    Rails.logger.info "[ORDER] Auto-completed order ##{order_number} (#{order_type})"
    true
  rescue => e
    Rails.logger.error "[ORDER] Failed to complete order ##{order_number}: #{e.message}"
    false
  end

end