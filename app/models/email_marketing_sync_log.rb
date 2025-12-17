# frozen_string_literal: true

class EmailMarketingSyncLog < ApplicationRecord
  include TenantScoped

  acts_as_tenant(:business)
  belongs_to :business
  belongs_to :email_marketing_connection

  # Sync types
  enum :sync_type, {
    full_sync: 0,        # Sync all customers
    incremental: 1,      # Sync only changed customers since last sync
    single_contact: 2,   # Sync a single contact
    batch: 3             # Sync a batch of contacts
  }, prefix: true

  # Status
  enum :status, {
    pending: 0,
    running: 1,
    completed: 2,
    failed: 3,
    partially_completed: 4
  }, prefix: true

  # Direction
  enum :direction, {
    outbound: 0,  # BizBlasts → Email Platform
    inbound: 1    # Email Platform → BizBlasts (webhook updates)
  }, prefix: true

  # Validations
  validates :sync_type, presence: true
  validates :status, presence: true

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(status: [:completed, :partially_completed]) }
  scope :failed_logs, -> { where(status: :failed) }

  def start!
    update!(
      status: :running,
      started_at: Time.current
    )
  end

  def complete!(summary = {})
    final_status = contacts_failed > 0 ? :partially_completed : :completed
    update!(
      status: final_status,
      completed_at: Time.current,
      summary: summary
    )
  end

  def fail!(error_message)
    errors_list = error_details || []
    errors_list << { message: error_message, occurred_at: Time.current.iso8601 }
    update!(
      status: :failed,
      completed_at: Time.current,
      error_details: errors_list
    )
  end

  def add_error(error)
    errors_list = error_details || []
    errors_list << { message: error.to_s, occurred_at: Time.current.iso8601 }
    update!(error_details: errors_list)
  end

  def increment_synced!
    increment!(:contacts_synced)
  end

  def increment_created!
    increment!(:contacts_created)
    increment!(:contacts_synced)
  end

  def increment_updated!
    increment!(:contacts_updated)
    increment!(:contacts_synced)
  end

  def increment_failed!
    increment!(:contacts_failed)
  end

  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end

  def duration_formatted
    return 'N/A' unless duration
    if duration < 60
      "#{duration.round(1)}s"
    else
      "#{(duration / 60).round(1)}m"
    end
  end

  def success_rate
    return 0 if contacts_synced.zero? && contacts_failed.zero?
    total = contacts_synced + contacts_failed
    ((contacts_synced.to_f / total) * 100).round(1)
  end
end
