# frozen_string_literal: true

class AdpPayrollExportConfig < ApplicationRecord
  acts_as_tenant(:business)

  belongs_to :business

  validates :business_id, presence: true
  validates :active, inclusion: { in: [true, false] }
  validates :rounding_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :round_total_hours, inclusion: { in: [true, false] }

  scope :active, -> { where(active: true) }

  def included_booking_statuses
    raw = config.fetch('included_booking_statuses', nil)
    return %w[completed] if raw.blank?
    Array(raw).map(&:to_s)
  end

  def default_pay_code
    config.fetch('default_pay_code', 'REG').to_s
  end

  def timezone
    config.fetch('timezone', business&.time_zone.presence || Time.zone.name).to_s
  end

  def round_to_minutes
    rounding_minutes.to_i
  end
end
