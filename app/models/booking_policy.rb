# frozen_string_literal: true

class BookingPolicy < ApplicationRecord
  belongs_to :business

  # Basic validations - can be refined later
  validates :cancellation_window_mins, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :buffer_time_mins, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :max_daily_bookings, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :max_advance_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # Consider adding serialization for intake_fields if complex structure is needed
  # serialize :intake_fields, JSON
end 