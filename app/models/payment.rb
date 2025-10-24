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
  
  def orphaned_payment?
    business_id.nil? || tenant_customer_id.nil? || invoice_id.nil?
  end
end
