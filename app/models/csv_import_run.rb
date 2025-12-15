# frozen_string_literal: true

class CsvImportRun < ApplicationRecord
  acts_as_tenant(:business)

  belongs_to :business
  belongs_to :user, optional: true
  has_one_attached :csv_file

  enum :status, {
    queued: 0,
    running: 1,
    succeeded: 2,
    failed: 3,
    partial: 4
  }

  IMPORT_TYPES = %w[
    customers bookings invoices orders
    payments products services customer_subscriptions
  ].freeze

  validates :business_id, presence: true
  validates :import_type, presence: true, inclusion: { in: IMPORT_TYPES }
  validates :csv_file, presence: true, on: :create

  def start!
    update!(status: :running, started_at: Time.current)
  end

  def succeed!(summary: {})
    update!(
      status: :succeeded,
      finished_at: Time.current,
      summary: summary
    )
  end

  def fail!(error_report: {})
    update!(
      status: :failed,
      finished_at: Time.current,
      error_report: error_report
    )
  end

  def partial!(summary: {}, error_report: {})
    update!(
      status: :partial,
      finished_at: Time.current,
      summary: summary,
      error_report: error_report
    )
  end

  def progress_percentage
    return 0 if total_rows.zero?
    ((processed_rows.to_f / total_rows) * 100).round
  end

  def increment_progress!(created: false, updated: false, skipped: false, error: false)
    updates = { processed_rows: processed_rows + 1 }
    updates[:created_count] = created_count + 1 if created
    updates[:updated_count] = updated_count + 1 if updated
    updates[:skipped_count] = skipped_count + 1 if skipped
    updates[:error_count] = error_count + 1 if error
    update_columns(updates)
  end
end
