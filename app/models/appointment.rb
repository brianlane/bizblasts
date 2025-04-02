# frozen_string_literal: true

class Appointment < ApplicationRecord
  belongs_to :company
  belongs_to :service
  belongs_to :service_provider # Note: This model was in the migration but we haven't created it yet.
  belongs_to :customer

  # Validations based on the migration schema
  validates :company, presence: true
  validates :service, presence: true
  validates :service_provider, presence: true
  validates :customer, presence: true
  # client_name, client_email, client_phone are from the migration, may duplicate Customer data
  validates :client_name, presence: true 
  validates :start_time, presence: true
  validates :end_time, presence: true
  # Consider adding validation for status values if using specific ones
  # validates :status, inclusion: { in: %w[scheduled completed cancelled no-show], message: "%\{value} is not a valid status" }

  validate :end_time_after_start_time

  private

  def end_time_after_start_time
    return if end_time.blank? || start_time.blank?

    errors.add(:end_time, "must be after the start time") if end_time <= start_time
  end
end 