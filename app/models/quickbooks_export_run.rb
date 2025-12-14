# frozen_string_literal: true

class QuickbooksExportRun < ApplicationRecord
  acts_as_tenant(:business)

  belongs_to :business
  belongs_to :user, optional: true

  enum :status, {
    queued: 0,
    running: 1,
    succeeded: 2,
    failed: 3,
    partial: 4
  }

  validates :business_id, presence: true
  validates :status, presence: true
  validates :export_type, presence: true

  def start!
    update!(status: :running, started_at: Time.current)
  end

  def succeed!(summary: {}, error_report: {})
    update!(status: :succeeded, finished_at: Time.current, summary: summary, error_report: error_report)
  end

  def fail!(error_report: {})
    update!(status: :failed, finished_at: Time.current, error_report: error_report)
  end

  def partial!(summary: {}, error_report: {})
    update!(status: :partial, finished_at: Time.current, summary: summary, error_report: error_report)
  end
end
