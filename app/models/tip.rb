class Tip < ApplicationRecord
  include TenantScoped
  
  belongs_to :business, required: true
  belongs_to :booking, required: true
  belongs_to :tenant_customer, required: true
  
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :booking_id, uniqueness: { scope: :business_id }
  validates :business, presence: true
  validates :stripe_fee_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :platform_fee_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :business_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
  enum :status, {
    pending: 0,
    completed: 1,
    failed: 2
  }
  
  scope :successful, -> { where(status: :completed) }
  scope :pending, -> { where(status: :pending) }
  
  # Calculate fees before saving
  before_save :calculate_fees, if: :amount_changed?
  
  def mark_as_completed!
    update(status: :completed, paid_at: Time.current)
  end
  
  def mark_as_failed!(reason = nil)
    update(status: :failed, failure_reason: reason)
  end
  
  # Check if tip is eligible (service completed)
  def eligible_for_payment?
    return false unless booking.present?
    # Updated: Removed experience-only restriction, now all service types can be tipped
    # Previously: Required booking.service&.experience?
    return false unless booking.service&.tips_enabled?
    
    # Check if service is completed (start_time + duration has passed)
    service_end_time = booking.start_time + booking.service.duration.minutes
    Time.current >= service_end_time
  end
  
  # Calculate total fees
  def total_fees
    (stripe_fee_amount || 0) + (platform_fee_amount || 0)
  end
  
  # Calculate business net amount after fees
  def net_business_amount
    amount - total_fees
  end
  
  def self.ransackable_attributes(auth_object = nil)
    %w[id amount stripe_fee_amount platform_fee_amount business_amount status paid_at created_at updated_at business_id booking_id tenant_customer_id]
  end
  
  def self.ransackable_associations(auth_object = nil)
    %w[business booking tenant_customer]
  end
  
  private
  
  def calculate_fees
    return unless amount.present? && business.present?
    
    amount_cents = (amount * 100).to_i
    
    # Calculate Stripe fee (2.9% + $0.30)
    stripe_percentage_fee = (amount_cents * 0.029).round
    self.stripe_fee_amount = (stripe_percentage_fee + 30) / 100.0
    
    # Calculate BizBlasts platform fee
    self.platform_fee_amount = (amount_cents * BizBlasts::PLATFORM_FEE_RATE).round / 100.0
    
    # Calculate net amount business receives after all fees
    self.business_amount = amount - stripe_fee_amount - platform_fee_amount
  end
end 