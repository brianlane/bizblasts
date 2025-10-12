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
  
  # Remaining balance after all successful payments. Use total_amount
  # (which includes taxes, tips, etc.) to avoid negative balances when
  # amount represents a pre-tax subtotal.
  def balance_due
    total_amount - total_paid
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
    %w[amount business_id created_at due_date guest_access_token id invoice_number original_amount discount_amount status tenant_customer_id total_amount updated_at tax_amount tip_amount review_request_suppressed]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[booking business line_items order payments promotion shipping_method tax_rate tenant_customer]
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
    
    self.total_amount = self.amount + (self.tax_amount || 0) + (self.tip_amount || 0)
  end

  before_validation :calculate_totals
  before_validation :set_invoice_number, on: :create
  before_validation :set_guest_access_token, on: :create
  after_create :send_invoice_created_email
  after_update :send_review_request_email, if: :saved_change_to_status_to_paid?

  # Tip-related methods
  def has_tip_eligible_items?
    order&.has_tip_eligible_items? || false
  end

  def tip_eligible_items
    order&.tip_eligible_items || []
  end

  def tip_enabled?
    has_tip_eligible_items?
  end

  # Check if status changed to paid
  def saved_change_to_status_to_paid?
    saved_change_to_status? && status == 'paid'
  end
  
  private
  
  # Send review request email after invoice is paid
  def send_review_request_email
    # Skip if review requests are suppressed for this invoice
    return if review_request_suppressed?
    
    # Skip if business doesn't have Google Place ID configured
    return unless business&.google_place_id.present?
    
    # Skip if customer can't receive emails
    return unless tenant_customer&.can_receive_email?(:customer)
    
    # Generate signed tracking token for unsubscribe
    tracking_token = generate_review_request_tracking_token
    return unless tracking_token
    
    begin
      # Prepare request data for mailer
      request_data = {
        business: business,
        customer: tenant_customer,
        booking: booking,
        order: order,
        invoice: self,
        tracking_token: tracking_token
      }
      
      # Send the review request email (check for NullMail to avoid sending non-existent emails)
      mail = ReviewRequestMailer.review_request_email(request_data)
      
      # Check if the mail is actually a NullMail (validation failed, ineligible customer, etc.)
      if mail&.message&.is_a?(ActionMailer::Base::NullMail)
        Rails.logger.info "[ReviewRequest] Review request email skipped for Invoice ##{invoice_number} (validation failed or ineligible)"
        return
      elsif mail.present?
        mail.deliver_later(queue: 'mailers')
        Rails.logger.info "[ReviewRequest] Review request email enqueued for Invoice ##{invoice_number} to #{tenant_customer.email}"

        # Send SMS review request if customer can receive SMS
        begin
          if tenant_customer.can_receive_sms?(:review_request)
            # Generate the Google review URL
            review_url = "https://search.google.com/local/writereview?placeid=#{business.google_place_id}"

            # Determine service name for personalization
            service_name = if booking&.service
              booking.service.name
            elsif order&.service_line_items&.any?
              service_names = order.service_line_items.map { |item| item.service&.name }.compact
              service_names.first # Use first service name for simplicity
            else
              "our service"
            end

            # Send review request SMS
            SmsService.send_review_request(tenant_customer, business, service_name, review_url)
            Rails.logger.info "[ReviewRequest] Review request SMS sent for Invoice ##{invoice_number} to #{tenant_customer.phone}"
          end
        rescue => sms_error
          Rails.logger.error "[ReviewRequest] Failed to send review request SMS for Invoice ##{invoice_number}: #{sms_error.message}"
          # Don't fail the whole review request process for SMS issues
        end
      else
        # This shouldn't happen with current mailer implementation, but kept for safety
        Rails.logger.warn "[ReviewRequest] Mailer returned nil for Invoice ##{invoice_number}; email not enqueued"
        return
      end
    rescue => e
      Rails.logger.error "[ReviewRequest] Failed to send review request email for Invoice ##{invoice_number}: #{e.message}"
    end
  end
  
  # Generate signed tracking token for review request unsubscribe
  def generate_review_request_tracking_token
    return nil unless tenant_customer && business
    
    token_data = {
      business_id: business.id,
      customer_id: tenant_customer.id,
      invoice_id: id,
      booking_id: booking&.id,
      order_id: order&.id,
      generated_at: Time.current.to_i
    }
    
    # Use Rails message verifier to create signed token
    verifier = Rails.application.message_verifier('review_request_tracking')
    verifier.generate(token_data)
  rescue => e
    Rails.logger.error "[ReviewRequest] Failed to generate tracking token for Invoice ##{invoice_number}: #{e.message}"
    nil
  end

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

  def send_invoice_created_email
    # Only send for pending invoices (not for paid invoices created after payment)
    # Available for all tiers
    return unless status == 'pending'
    
    # Skip automatic email if this invoice belongs to an order
    # Order creation handles staggered email delivery to avoid rate limits
    if order.present?
      Rails.logger.info "[EMAIL] Skipping automatic invoice email for Order-based Invoice ##{invoice_number} (handled by order)"
      return
    end
    
    begin
      NotificationService.invoice_created(self)
      Rails.logger.info "[NOTIFICATION] Sent invoice created notifications for Invoice ##{invoice_number}"
    rescue => e
      Rails.logger.error "[NOTIFICATION] Failed to send invoice created notifications for Invoice ##{invoice_number}: #{e.message}"
    end
  end
end 