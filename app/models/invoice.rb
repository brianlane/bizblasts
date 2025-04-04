class Invoice < ApplicationRecord
  include TenantScoped
  
  belongs_to :tenant_customer
  belongs_to :booking, optional: true
  belongs_to :promotion, optional: true
  has_many :payments, dependent: :destroy
  
  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :due_date, presence: true
  validates :status, presence: true
  validates :invoice_number, presence: true, uniqueness: { scope: :business_id }
  validates :original_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :discount_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
  enum :status, {
    draft: 0,
    pending: 1,
    paid: 2,
    overdue: 3,
    cancelled: 4
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
    update(status: :paid, paid_at: Time.current)
  end
  
  def send_reminder
    InvoiceReminderJob.perform_later(id)
  end
  
  def check_overdue
    update(status: :overdue) if pending? && due_date < Time.current
  end

  def self.ransackable_attributes(auth_object = nil)
    super + %w[original_amount discount_amount]
  end

  def self.ransackable_associations(auth_object = nil)
    super + %w[promotion]
  end
end 