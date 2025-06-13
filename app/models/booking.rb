# frozen_string_literal: true

class Booking < ApplicationRecord
  include TenantScoped
  include BookingStatus
  include BookingScopes
  include BookingValidations
  
  # Callbacks
  after_save :schedule_tip_reminder_if_needed
  
  acts_as_tenant(:business)
  belongs_to :business, optional: true
  belongs_to :service, optional: true
  belongs_to :staff_member, optional: true
  belongs_to :tenant_customer, optional: true
  accepts_nested_attributes_for :tenant_customer
  belongs_to :promotion, optional: true
  has_one :invoice, dependent: :nullify
  has_one :tip, dependent: :destroy
  has_many :booking_product_add_ons, dependent: :destroy
  has_many :add_on_product_variants, through: :booking_product_add_ons, source: :product_variant
  accepts_nested_attributes_for :booking_product_add_ons, allow_destroy: true,
                                reject_if: proc { |attributes| attributes['quantity'].to_i <= 0 || attributes['product_variant_id'].blank? }
  
  # Add quantity for multi-client bookings
  attribute :quantity, :integer, default: 1

  # Validations
  validates :quantity, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :quantity, numericality: { less_than_or_equal_to: :service_max_bookings }, if: :experience_service?
  validates :quantity, numericality: { greater_than_or_equal_to: :service_min_bookings }, if: :experience_service?

  # Override TenantScoped validation to allow nil business for orphaned bookings
  validates :business, presence: true, unless: :business_deleted?

  delegate :name, to: :service, prefix: true, allow_nil: true
  delegate :name, to: :staff_member, prefix: true, allow_nil: true
  delegate :name, :email, to: :tenant_customer, prefix: :customer, allow_nil: true
  
  def total_charge
    service_cost = (self.service&.price || 0) * self.quantity.to_i
    # Use database sum to safely handle nil values
    addons_cost = self.booking_product_add_ons.sum(:total_amount) || 0
    service_cost + addons_cost
  end
  
  # Check if tips are enabled and booking is eligible for tips
  def eligible_for_tips?
    return false unless business&.tips_enabled?
    return false unless service&.experience?
    return false unless service&.tips_enabled?
    
    true
  end
  
  # Check if tip has already been processed
  def tip_processed?
    tip&.completed?
  end
  
  # Generate secure token for tip collection
  def generate_tip_token
    # Create a secure token that expires in 7 days
    payload = {
      booking_id: id,
      exp: 7.days.from_now.to_i,
      iat: Time.current.to_i
    }
    JWT.encode(payload, Rails.application.secret_key_base, 'HS256')
  end

  # Verify tip token
  def self.verify_tip_token(token)
    payload = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: 'HS256')[0]
    find(payload['booking_id']) if payload['booking_id']
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil
  end

  # Schedule experience tip reminder after completion
  def schedule_experience_tip_reminder
    return unless completed? && service&.experience? && service&.tips_enabled?
    return unless business.tips_enabled?
    return if tip.present? # Don't send if tip already collected
    
    # Schedule reminder for 2 hours after completion
    ExperienceTipReminderJob.set(wait: 2.hours).perform_later(id)
  end
  
  private

  def experience_service?
    self.service&.experience?
  end

  def service_min_bookings
    self.service&.min_bookings || 1 # Default to 1 if not set on service
  end

  def service_max_bookings
    self.service&.max_bookings || Float::INFINITY # Default to infinity if not set on service
  end
  
  # Define ransackable attributes for ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id start_time end_time status notes service_id staff_member_id tenant_customer_id 
       business_id created_at updated_at amount original_amount discount_amount cancellation_reason]
  end
  
  # Define ransackable associations for ActiveAdmin
  def self.ransackable_associations(auth_object = nil)
    %w[business service staff_member tenant_customer invoice promotion]
  end
  
  # --- Database Indexes Recommendation ---
  # To improve performance for availability checks and conflict detection,
  # it is highly recommended to add database indexes on columns used in queries
  # within the AvailabilityService, especially in fetch_conflicting_bookings.
  # Consider adding indexes on:
  # - staff_member_id
  # - start_time
  # - end_time
  # A composite index on staff_member_id and start_time or a GIST index for time ranges
  # might be particularly beneficial depending on query patterns.
  # Example migration: create_index :bookings, :staff_member_id
  # Example migration: add_index :bookings, [:start_time, :end_time], using: :gist
  # --- End Database Indexes Recommendation ---

  # Add callback for scheduling tip reminders
  def schedule_tip_reminder_if_needed
    if status_changed? && completed?
      schedule_experience_tip_reminder
    end
  end
end
