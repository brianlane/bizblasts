# frozen_string_literal: true

class CalendarSyncLog < ApplicationRecord
  belongs_to :calendar_event_mapping
  
  # Enum for sync actions
  enum :action, {
    event_create: 0,
    event_update: 1,
    event_delete: 2,
    event_import: 3,
    token_refresh: 4
  }
  
  # Enum for sync outcomes
  enum :outcome, {
    pending: 0,
    success: 1,
    failed: 2,
    skipped: 3
  }
  
  validates :calendar_event_mapping_id, presence: true
  validates :action, presence: true
  validates :outcome, presence: true
  
  scope :recent, -> { order(created_at: :desc) }
  scope :today, -> { where(created_at: Date.current.beginning_of_day..Date.current.end_of_day) }
  scope :failed_attempts, -> { where(outcome: :failed) }
  scope :successful_syncs, -> { where(outcome: :success) }
  
  delegate :booking, to: :calendar_event_mapping
  delegate :calendar_connection, to: :calendar_event_mapping
  delegate :provider, to: :calendar_connection
  delegate :staff_member, to: :calendar_connection
  delegate :business, to: :booking
  
  def self.log_sync_attempt(mapping, action, outcome, message = nil, metadata = {})
    create!(
      calendar_event_mapping: mapping,
      action: action,
      outcome: outcome,
      message: message,
      metadata: metadata.merge(timestamp: Time.current.iso8601)
    )
  end
  
  def self.success_rate_for_provider(provider, since: 24.hours.ago)
    logs = joins(calendar_event_mapping: :calendar_connection)
           .where(calendar_connections: { provider: provider })
           .where(created_at: since..)
    
    return 0 if logs.count.zero?
    
    success_count = logs.successful_syncs.count
    (success_count.to_f / logs.count * 100).round(2)
  end
  
  def self.recent_failures(limit: 10)
    failed_attempts.recent.limit(limit).includes(
      calendar_event_mapping: [:booking, :calendar_connection]
    )
  end
  
  def action_description
    case action
    when 'event_create'
      'Creating calendar event'
    when 'event_update'
      'Updating calendar event'
    when 'event_delete'
      'Deleting calendar event'
    when 'event_import'
      'Importing external events'
    when 'token_refresh'
      'Refreshing OAuth token'
    else
      action.humanize
    end
  end
  
  def outcome_description
    case outcome
    when 'pending'
      'In progress'
    when 'success'
      'Completed successfully'
    when 'failed'
      'Failed'
    when 'skipped'
      'Skipped'
    else
      outcome.humanize
    end
  end
  
  def duration
    return nil unless metadata['started_at'] && metadata['completed_at']
    
    start_time = Time.parse(metadata['started_at'])
    end_time = Time.parse(metadata['completed_at'])
    end_time - start_time
  rescue ArgumentError
    nil
  end
  
  def error_details
    return nil unless failed?
    
    {
      message: message,
      error_type: metadata['error_type'],
      error_code: metadata['error_code'],
      retry_count: metadata['retry_count'] || 0
    }
  end
  
  def formatted_metadata
    return {} if metadata.blank?
    
    metadata.except('timestamp').transform_keys(&:humanize)
  end
  
  def can_be_retried?
    failed? && created_at > 1.hour.ago
  end
end