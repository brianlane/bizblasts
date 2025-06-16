# frozen_string_literal: true

class SubscriptionTransaction < ApplicationRecord
  include TenantScoped
  
  # Associations
  belongs_to :customer_subscription
  belongs_to :business
  belongs_to :tenant_customer
  belongs_to :order, optional: true
  belongs_to :booking, optional: true
  belongs_to :invoice, optional: true
  belongs_to :payment, optional: true
  
  # Enums
  enum :transaction_type, {
    billing: 'billing',
    payment: 'payment',
    refund: 'refund',
    failed_payment: 'failed_payment',
    skipped: 'skipped',
    loyalty_awarded: 'loyalty_awarded',
    cancelled: 'cancelled',
    reactivated: 'reactivated'
  }
  
  enum :status, {
    pending: 0,
    completed: 1,
    failed: 2,
    cancelled: 3,
    retrying: 4
  }, prefix: :status
  
  # Validations
  validates :transaction_type, presence: true
  validates :status, presence: true
  validates :processed_date, presence: true, unless: :status_pending?
  validates :amount, numericality: true, allow_nil: true
  validates :retry_count, numericality: { greater_than_or_equal_to: 0 }
  
  # Custom validation for amount based on transaction type
  validate :validate_amount_for_transaction_type
  
  # Scopes
  scope :recent, -> { order(processed_date: :desc) }
  scope :completed, -> { where(status: :completed) }
  scope :failed, -> { where(status: :failed) }
  scope :pending, -> { where(status: :pending) }
  scope :cancelled, -> { where(status: :cancelled) }
  scope :retrying, -> { where(status: :retrying) }
  scope :pending_retry, -> { where(status: :retrying, next_retry_at: ..Time.current) }
  scope :for_month, ->(date) { where(processed_date: date.beginning_of_month..date.end_of_month) }
  
  # Transaction type scopes
  scope :billing, -> { where(transaction_type: :billing) }
  scope :refund, -> { where(transaction_type: :refund) }
  scope :payment, -> { where(transaction_type: :payment) }
  
  # Callbacks
  before_save :set_processed_date_on_completion
  
  # Instance methods
  def success?
    status_completed?
  end
  
  def processed?
    processed_date.present?
  end
  
  def can_retry?
    status_failed? && retry_count < 3 && next_retry_at.present? && next_retry_at <= Time.current
  end
  
  def schedule_retry!
    return unless status_failed? && retry_count < 3
    
    increment(:retry_count)
    self.next_retry_at = calculate_next_retry_time
    self.status = :retrying
    save!
  end
  
    def mark_completed!(notes = nil)
    update!(
      status: :completed,
      notes: [self.notes, notes].compact.join("; "),
      next_retry_at: nil
    )
  end

  def mark_failed!(reason)
    update!(
      status: :failed,
      failure_reason: reason,
      next_retry_at: calculate_next_retry_time
    )
  end
  
  # Ransack configuration
  def self.ransackable_attributes(auth_object = nil)
    %w[id customer_subscription_id business_id tenant_customer_id transaction_type status 
       processed_date amount created_at updated_at]
  end
  
  def self.ransackable_associations(auth_object = nil)
    %w[customer_subscription business tenant_customer order booking invoice payment]
  end
  
  private
  
  def calculate_next_retry_time
    case retry_count
    when 0
      1.hour.from_now
    when 1
      4.hours.from_now
    when 2
      1.day.from_now
    else
      nil # No more retries
    end
  end
  
  def validate_amount_for_transaction_type
    return unless amount.present?
    
    if transaction_type == "refund"
      # Refunds can be negative or positive
      return
    else
      # Other transaction types should have positive amounts
      errors.add(:amount, "must be greater than or equal to 0") if amount < 0
    end
  end
  
  def set_processed_date_on_completion
    if status_changed? && (status_completed? || status_failed?)
      # Only set processed_date if it's not already today's date
      if processed_date.blank? || processed_date != Date.current
        self.processed_date = Time.current.to_date
      end
    end
  end
end 