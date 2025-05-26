class Payment < ApplicationRecord
  include TenantScoped
  
  belongs_to :business
  belongs_to :invoice
  belongs_to :order, optional: true
  belongs_to :tenant_customer
  
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :payment_method, presence: true, if: :completed?
  validates :status, presence: true
  
  enum :payment_method, {
    credit_card: 0,
    cash: 1,
    bank_transfer: 2,
    paypal: 3,
    other: 4
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
end
