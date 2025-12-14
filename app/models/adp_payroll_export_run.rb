# frozen_string_literal: true

class AdpPayrollExportRun < ApplicationRecord
  acts_as_tenant(:business)

  belongs_to :business
  belongs_to :user, optional: true

  enum :status, {
    queued: 0,
    running: 1,
    succeeded: 2,
    failed: 3
  }

  validates :business_id, presence: true
  validates :range_start, presence: true
  validates :range_end, presence: true

  validate :range_end_not_before_start

  def start!
    update!(status: :running, started_at: Time.current)
  end

  def succeed!(csv_data:, summary: {}, error_report: {})
    update!(status: :succeeded, finished_at: Time.current, csv_data: csv_data, summary: summary, error_report: error_report)
  end

  def fail!(error_report: {})
    update!(status: :failed, finished_at: Time.current, error_report: error_report)
  end

  private

  def range_end_not_before_start
    return if range_start.blank? || range_end.blank?
    return unless range_end < range_start

    errors.add(:range_end, 'must be on or after start date')
  end
end
