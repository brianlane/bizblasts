class Invoice < ApplicationRecord
  include TenantScoped
  
  belongs_to :tenant_customer
  belongs_to :booking, optional: true
  belongs_to :order, optional: true
  belongs_to :promotion, optional: true
  belongs_to :shipping_method, optional: true
  belongs_to :tax_rate, optional: true
  belongs_to :business, optional: true  # Allow nil for orphaned invoices
  has_many :payments, dependent: :destroy
  has_many :line_items, as: :lineable, dependent: :destroy
  
  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_amount, numericality: { greater_than_or_equal_to: 0.50, message: "must be at least $0.50 for Stripe payments" }, if: -> { stripe_payment_required? && !Rails.env.test? }
  validates :due_date, presence: true
  validates :status, presence: true
  validates :invoice_number, uniqueness: { scope: :business_id }
  validates :original_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :discount_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :booking_id, uniqueness: true, allow_nil: true
  
  # Override TenantScoped validation to allow nil business for orphaned invoices
  validates :business, presence: true, unless: :business_deleted?
  
  enum :status, {
    draft: 0,
    pending: 1,
    paid: 2,
    overdue: 3,
    cancelled: 4,
    business_deleted: 5
  }
  
  scope :unpaid, -> { where(status: [:pending, :overdue]) }
  scope :due_soon, -> { unpaid.where('due_date BETWEEN ? AND ?', Time.current, 7.days.from_now) }
  scope :overdue, -> { unpaid.where('due_date < ?', Time.current) }
  
  def total_paid
    payments.successful.sum(:amount)
  end
  
  def balance_due
    amount - total_paid
  end
  
  def mark_as_paid!
    update(status: :paid)
  end
  
  # Mark invoice as business deleted and remove associations
  def mark_business_deleted!
    ActsAsTenant.without_tenant do
      update_columns(
        status: 5, # business_deleted enum value
        business_id: nil,
        booking_id: nil,
        order_id: nil,
        shipping_method_id: nil,
        tax_rate_id: nil
      )
    end
  end
  
  def send_reminder
    InvoiceReminderJob.perform_later(id)
  end
  
  def check_overdue
    update(status: :overdue) if pending? && due_date < Time.current
  end

  # Check if this invoice requires Stripe payment (vs cash/other methods)
  def stripe_payment_required?
    # For now, assume all invoices may use Stripe unless specifically marked otherwise
    # You can customize this logic based on your business rules
    true
  end

  def self.ransackable_attributes(auth_object = nil)
    super + %w[original_amount discount_amount]
  end

  def self.ransackable_associations(auth_object = nil)
    super + %w[promotion shipping_method tax_rate]
  end

  def calculate_totals
    # Only calculate totals if we have data sources (booking, order, or line items)
    # This allows validation to catch missing required fields
    return unless booking.present? || order.present? || line_items.any?
    
    items_subtotal = 0
    if booking.present?
      items_subtotal = booking.total_charge
    elsif order.present?
      # For order-based invoices, use the order's calculated totals
      self.original_amount = order.total_amount - (order.tax_amount || 0)
      self.discount_amount = 0.0
      self.amount = self.original_amount - self.discount_amount
      self.tax_amount = order.tax_amount || 0
      self.total_amount = order.total_amount
      return # Skip the rest of the calculation since we're using order totals
    else
      items_subtotal = line_items.sum(&:total_amount)
    end
    
    self.original_amount = items_subtotal
    calculated_discount = self.promotion&.calculate_discount(original_amount) || self.discount_amount || 0
    self.discount_amount = calculated_discount
    self.amount = original_amount - calculated_discount
    
    current_tax_amount = 0
    if tax_rate.present?
      taxable_base = self.amount
      current_tax_amount = tax_rate.calculate_tax(taxable_base)
    end
    self.tax_amount = current_tax_amount || 0
    
    self.total_amount = self.amount + (self.tax_amount || 0)
  end

  before_validation :calculate_totals
  before_validation :set_invoice_number, on: :create
  before_validation :set_guest_access_token, on: :create

  private

  def set_invoice_number
    return if invoice_number.present?
    
    loop do
      self.invoice_number = "INV-#{SecureRandom.hex(6).upcase}"
      break unless self.class.exists?(business_id: self.business_id, invoice_number: self.invoice_number)
    end
  end

  def set_guest_access_token
    return if guest_access_token.present?
    
    # Generate a secure random token for guest access
    self.guest_access_token = SecureRandom.urlsafe_base64(32)
  end
end 