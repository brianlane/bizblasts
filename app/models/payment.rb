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
  
  private
  
  def orphaned_payment?
    business_id.nil? || tenant_customer_id.nil? || invoice_id.nil?
  end
end
