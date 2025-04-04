class Invoice < ApplicationRecord
  include TenantScoped
  
  belongs_to :customer
  belongs_to :booking, optional: true
  has_many :payments, dependent: :destroy
  
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :due_date, presence: true
  validates :status, presence: true
  
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
end 