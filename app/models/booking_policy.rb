# frozen_string_literal: true

class BookingPolicy < ApplicationRecord
  belongs_to :business

  # Basic validations - can be refined later
  validates :cancellation_window_mins, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :buffer_time_mins, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :max_daily_bookings, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :max_advance_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :min_duration_mins, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :max_duration_mins, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :min_advance_mins, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # Consider adding serialization for intake_fields if complex structure is needed
  # serialize :intake_fields, JSON

  validate :min_not_greater_than_max

  private

  def min_not_greater_than_max
    return if min_duration_mins.nil? || max_duration_mins.nil?
    if min_duration_mins > max_duration_mins
      errors.add(:min_duration_mins, 'cannot be greater than maximum duration')
    end
  end
end 