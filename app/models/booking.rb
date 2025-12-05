# frozen_string_literal: true

class Booking < ApplicationRecord
  include TenantScoped
  include BookingStatus
  include BookingScopes
  include BookingValidations
  
  # Callbacks
  after_save :schedule_tip_reminder_if_needed
  after_create :sync_to_calendar_async
  after_update :handle_calendar_sync_on_update
  before_destroy :remove_from_calendar_async
  
  acts_as_tenant(:business)
  belongs_to :business, optional: true
  belongs_to :service, optional: true
  belongs_to :staff_member, optional: true
  belongs_to :tenant_customer, optional: true
  accepts_nested_attributes_for :tenant_customer
  belongs_to :promotion, optional: true
  has_one :invoice, dependent: :nullify
  has_one :tip, dependent: :destroy
  has_one :client_document, as: :documentable, dependent: :nullify
  has_many :booking_product_add_ons, dependent: :destroy
  has_many :calendar_event_mappings, dependent: :destroy
  has_many :add_on_product_variants, through: :booking_product_add_ons, source: :product_variant
  accepts_nested_attributes_for :booking_product_add_ons, allow_destroy: true,
                                reject_if: proc { |attributes| attributes['quantity'].to_i <= 0 || attributes['product_variant_id'].blank? }
  belongs_to :service_variant, optional: true
  delegate :price, :duration, to: :service_variant, prefix: true, allow_nil: true
  
  # Add quantity for multi-client bookings
  attribute :quantity, :integer, default: 1

  # Calendar sync status enum
  enum :calendar_event_status, {
    not_synced: 0,
    sync_pending: 1,
    synced: 2,
    sync_failed: 3
  }, prefix: :calendar

  # Validations
  validates :quantity, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :quantity, numericality: { less_than_or_equal_to: :service_max_bookings }, if: :experience_service?
  validates :quantity, numericality: { greater_than_or_equal_to: :service_min_bookings }, if: :experience_service?

  # Override TenantScoped validation to allow nil business for orphaned bookings
  validates :business, presence: true, unless: :business_deleted?

  delegate :name, to: :service, prefix: true, allow_nil: true
  delegate :name, to: :staff_member, prefix: true, allow_nil: true
  delegate :full_name, :email, to: :tenant_customer, prefix: :customer, allow_nil: true
  
  def total_charge
    unit_price = (self.service_variant&.price || self.service&.price || 0)
    service_cost = unit_price * self.quantity.to_i
    # Use database sum to safely handle nil values
    addons_cost = self.booking_product_add_ons.sum(:total_amount) || 0
    service_cost + addons_cost
  end
  
  # Check if tips are enabled and booking is eligible for tips
  def eligible_for_tips?
    return false unless completed?
    return false unless service&.tips_enabled?
    return false if tip_processed?
    
    # Tips are now available for all service types (removed experience-only restriction)
    # Previously: Tips were only available for experience services (service.experience?)
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

  # Schedule tip reminder after completion (renamed from schedule_experience_tip_reminder)
  def schedule_tip_reminder
    return unless completed? && service&.tips_enabled?
    return if tip.present? # Don't send if tip already collected
    
    # Previously: Only for experience services (service&.experience?)
    # Now: Available for all service types with tips enabled
    
    # Schedule reminder for 2 hours after completion
    ExperienceTipReminderJob.set(wait: 2.hours).perform_later(id)
  end
  
  # Legacy method for backward compatibility - will be deprecated
  def schedule_experience_tip_reminder
    schedule_tip_reminder
  end
  
  # Returns the booking's time zone, preferring the associated business's configured zone.
  # Memoised to avoid repeated look-ups (which can trigger N+1 queries when business
  # isn't eager-loaded).
  def local_timezone
    @local_timezone ||= business&.time_zone.presence || Time.zone.name
  end

  # Get start time in the business's local timezone
  def local_start_time
    start_time&.in_time_zone(local_timezone)
  end

  # Get end time in the business's local timezone  
  def local_end_time
    end_time&.in_time_zone(local_timezone)
  end
  
  # Determine if booking can be refunded (i.e., has paid invoice with unrefunded payments)
  def refundable?
    return false if cancelled? || business_deleted?
    return false unless invoice
    invoice.payments.successful.where.not(status: :refunded).exists?
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

  # Calendar sync methods
  def calendar_sync_required?
    staff_member&.calendar_connections&.active&.any?
  end
  
  def calendar_sync_status_display
    case calendar_event_status
    when 'not_synced'
      'Not synced'
    when 'sync_pending'
      'Sync pending'
    when 'synced'
      'Synced'
    when 'sync_failed'
      'Sync failed'
    else
      'Unknown'
    end
  end
  
  def has_calendar_conflicts?
    return false unless staff_member && start_time && end_time
    
    ExternalCalendarEvent.conflicts_with_booking(self).exists?
  end
  
  def calendar_conflicts
    return ExternalCalendarEvent.none unless staff_member && start_time && end_time
    
    ExternalCalendarEvent.conflicts_with_booking(self)
  end

  # Calendar sync callback methods
  def sync_to_calendar_async
    return unless calendar_sync_required?
    return if calendar_synced?
    
    update_column(:calendar_event_status, :sync_pending)
    Calendar::SyncBookingJob.perform_later(id)
  end
  
  def handle_calendar_sync_on_update
    return unless calendar_sync_required?
    
    # Check if relevant fields changed
    relevant_changes = %w[start_time end_time service_id staff_member_id tenant_customer_id notes status]
    
    if (saved_changes.keys & relevant_changes).any?
      if cancelled? || business_deleted?
        remove_from_calendar_async
      else
        update_column(:calendar_event_status, :sync_pending) unless calendar_sync_pending?
        Calendar::SyncBookingJob.perform_later(id)
      end
    end
  end
  
  def remove_from_calendar_async
    return unless calendar_event_mappings.any?
    
    Calendar::DeleteBookingJob.perform_later(id, business_id)
  end

  # Add callback for scheduling tip reminders
  def schedule_tip_reminder_if_needed
    if status_changed? && completed?
      # Updated to use new method that works for all service types
      schedule_tip_reminder
    end
  end
end
