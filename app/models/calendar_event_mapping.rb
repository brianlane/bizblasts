# frozen_string_literal: true

class CalendarEventMapping < ApplicationRecord
  belongs_to :booking
  belongs_to :calendar_connection
  has_many :calendar_sync_logs, dependent: :destroy
  
  # Enum for sync status
  enum :status, {
    pending: 0,
    synced: 1,
    failed: 2,
    deleted: 3
  }
  
  validates :booking_id, presence: true
  validates :calendar_connection_id, presence: true
  validates :external_event_id, presence: true
  validates :status, presence: true
  
  # Ensure one mapping per booking per calendar connection
  validates :booking_id, uniqueness: { scope: :calendar_connection_id }
  
  scope :recent, -> { order(created_at: :desc) }
  scope :needs_sync, -> { where(status: [:pending, :failed]) }
  scope :successfully_synced, -> { where(status: :synced) }
  
  delegate :business, to: :booking
  delegate :staff_member, to: :calendar_connection
  delegate :provider, to: :calendar_connection
  delegate :provider_display_name, to: :calendar_connection
  
  # Callbacks
  after_create :log_creation
  after_update :log_status_change, if: :saved_change_to_status?
  
  def mark_synced!(external_event_id = nil)
    updates = { status: :synced, last_synced_at: Time.current }
    updates[:external_event_id] = external_event_id if external_event_id.present?
    update!(updates)
  end
  
  def mark_failed!(error_message)
    update!(
      status: :failed,
      last_error: error_message,
      last_synced_at: Time.current
    )
  end
  
  def mark_deleted!
    update!(status: :deleted, last_synced_at: Time.current)
  end
  
  def retry_sync!
    update!(status: :pending, last_error: nil)
  end
  
  def sync_overdue?
    return true if last_synced_at.blank?
    last_synced_at < 1.hour.ago
  end
  
  def last_sync_attempt
    last_synced_at || created_at
  end
  
  def error_summary
    return nil if last_error.blank?
    # Truncate long error messages for display
    last_error.length > 100 ? "#{last_error[0..97]}..." : last_error
  end
  
  def can_retry?
    failed? && created_at > 24.hours.ago
  end
  
  # Get the most recent sync log entry
  def latest_sync_log
    calendar_sync_logs.order(created_at: :desc).first
  end
  
  # Check if this mapping represents a booking that has been cancelled
  def booking_cancelled?
    booking&.cancelled?
  end
  
  # Check if this mapping represents a booking that has been completed
  def booking_completed?
    booking&.completed?
  end
  
  private
  
  def log_creation
    calendar_sync_logs.create!(
      action: :create,
      outcome: :pending,
      message: "Calendar event mapping created for #{provider_display_name}",
      metadata: {
        booking_id: booking_id,
        external_event_id: external_event_id,
        provider: provider
      }
    )
  end
  
  def log_status_change
    calendar_sync_logs.create!(
      action: :update,
      outcome: status,
      message: "Status changed to #{status}",
      metadata: {
        previous_status: status_before_last_save,
        new_status: status,
        error: last_error
      }
    )
  end
end