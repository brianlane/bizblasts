class Payment < ApplicationRecord
  include TenantScoped
  
  belongs_to :business, optional: true
  belongs_to :invoice, optional: true
  belongs_to :order, optional: true
  belongs_to :tenant_customer, optional: true
  
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :payment_method, presence: true
  validates :status, presence: true
  
  validates :business, presence: true, unless: :orphaned_payment?
  validates :tenant_customer, presence: true, unless: :orphaned_payment?
  validates :invoice, presence: true, unless: :orphaned_payment?

  # Callbacks
  after_commit :clear_customer_revenue_cache, on: [:create, :update, :destroy]

  enum :payment_method, {
    credit_card: 'credit_card',
    cash: 'cash',
    bank_transfer: 'bank_transfer',
    paypal: 'paypal',
    other: 'other'
  }
  
  enum :status, {
    pending: 0,
    completed: 1,
    failed: 2,
    refunded: 3
  }
  
  scope :successful, -> { where(status: :completed) }
  scope :pending, -> { where(status: :pending) }
  
  def mark_as_completed!
    update(status: :completed, completed_at: Time.current)
  end
  
  def refund!
    update(status: :refunded)
  end
  
  # Initiate a refund for this payment using StripeService. Returns the Stripe::Refund
  # object on success, or false on failure. This will only run for completed payments
  # that were processed through Stripe (stripe_payment_intent_id must be present).
  #
  # Params:
  #   amount [Float]   – Optional partial refund amount in dollars. Defaults to full amount.
  #   reason [String]  – Optional reason text ("requested_by_customer", "duplicate", etc.).
  #   user   [User]    – Optional user initiating the refund (for auditing). Currently stored
  #                      only in logs – extend as needed.
  def initiate_refund(amount: nil, reason: nil, user: nil)
    unless completed?
      errors.add(:base, "Only completed payments can be refunded")
      return false
    end

    unless stripe_payment_intent_id.present?
      errors.add(:base, "Payment is missing Stripe payment intent – cannot refund via Stripe")
      return false
    end

    SecureLogger.info("[PAYMENT] Initiating refund for Payment ##{id} by #{user&.email || 'system'} – amount=#{amount || self.amount}, reason=#{reason}")

    begin
      result = StripeService.create_refund(self, amount: amount, reason: reason)
      return result
    rescue => e
      Rails.logger.error("[PAYMENT] Refund failed for Payment ##{id}: #{e.message}")
      errors.add(:base, "Stripe refund failed: #{e.message}")
      return false
    end
  end
  
  # Mark payment as business deleted and remove business association
  def mark_business_deleted!
    ActsAsTenant.without_tenant do
      update_columns(
        business_id: nil,
        tenant_customer_id: nil,
        invoice_id: nil
      )
    end
  end
  
  def self.ransackable_attributes(auth_object = nil)
    [
      "amount",
      "business_amount",
      "business_id",
      "created_at",
      "failure_reason",
      "id",
      "id_value",
      "invoice_id",
      "order_id",
      "paid_at",
      "payment_method",
      "platform_fee_amount",
      "refund_reason",
      "refunded_amount",
      "status",
      "stripe_charge_id",
      "stripe_customer_id",
      "stripe_fee_amount",
      "stripe_payment_intent_id",
      "stripe_transfer_id",
      "tenant_customer_id",
      "tip_amount",
      "tip_received_on_initial_payment",
      "tip_amount_received_initially",
      "updated_at"
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    ["business", "invoice", "order", "tenant_customer"]
  end
  
  private

  def clear_customer_revenue_cache
    return unless tenant_customer

    tenant_customer.clear_revenue_cache

    # Update cached analytics fields asynchronously to avoid slowing down payment processing
    # Trigger update if:
    # 1. Payment status changed to completed or refunded (adds revenue to analytics)
    # 2. Payment status changed FROM completed or refunded to something else (removes revenue)
    # 3. A completed/refunded payment was destroyed (removes revenue from analytics)
    status_changed_to_counted = saved_change_to_status? && (completed? || refunded?)
    status_changed_from_counted = saved_change_to_status? &&
                                  %w[completed refunded].include?(status_before_last_save)
    destroyed_while_counted = destroyed? && (completed? || refunded?)

    should_update_cache = status_changed_to_counted ||
                          status_changed_from_counted ||
                          destroyed_while_counted

    if should_update_cache
      UpdateCustomerAnalyticsCacheJob.perform_later(tenant_customer.id)
    end
  end

  def orphaned_payment?
    business_id.nil? || tenant_customer_id.nil? || invoice_id.nil?
  end
end
