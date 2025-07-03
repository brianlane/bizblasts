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
    update(status: :refunded, refunded_at: Time.current)
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
    ["amount", "business_amount", "business_id", "created_at", "failure_reason", "id", "id_value", "invoice_id", "order_id", "paid_at", "payment_method", "platform_fee_amount", "refund_reason", "refunded_amount", "status", "stripe_charge_id", "stripe_customer_id", "stripe_fee_amount", "stripe_payment_intent_id", "stripe_transfer_id", "tenant_customer_id", "tip_amount", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["business", "invoice", "order", "tenant_customer"]
  end
  
  private
  
  def orphaned_payment?
    business_id.nil? || tenant_customer_id.nil? || invoice_id.nil?
  end
end
