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
  # Removed client_name, client_email, client_phone validations as they duplicate Customer data
  validates :start_time, presence: true
  validates :end_time, presence: true
  # Ensure status is one of the allowed values
  validates :status, inclusion: { in: %w[scheduled completed cancelled no-show], message: "%\{value} is not a valid status" }
  # Add price validation
  validates :price, numericality: { greater_than_or_equal_to: 0, allow_nil: true }

  validate :end_time_after_start_time
  validate :service_provider_available, if: -> { service_provider.present? && start_time.present? && end_time.present? }
  
  # Valid status values for filtering and validation
  VALID_STATUSES = %w[scheduled completed cancelled no-show].freeze
  
  # Check if a status value is valid
  # @param status [String] the status to check
  # @return [Boolean] true if valid, false otherwise
  def valid_status?(status)
    VALID_STATUSES.include?(status.to_s)
  end

  private

  def end_time_after_start_time
    return if end_time.blank? || start_time.blank?

    errors.add(:end_time, "must be after the start time") if end_time <= start_time
  end
  
  # Validate that the service provider is available for the entire appointment duration
  def service_provider_available
    # Skip validation for status other than 'scheduled'
    return if status.present? && status != 'scheduled'
    
    # Check if this is an existing appointment being updated
    if persisted?
      # If we're not changing the times or provider, skip validation
      old_appointment = Appointment.find(id)
      if old_appointment.service_provider_id == service_provider_id &&
         old_appointment.start_time == start_time &&
         old_appointment.end_time == end_time
        return
      end
    end
    
    # Check availability at the start time
    unless service_provider.available_at?(start_time)
      errors.add(:start_time, "is outside of service provider's available hours")
      return
    end
    
    # For longer appointments, check availability at 30-minute intervals
    # to ensure the provider is available throughout the appointment
    check_time = start_time + 30.minutes
    
    while check_time < end_time
      unless service_provider.available_at?(check_time)
        errors.add(:base, "Service provider is not available for the entire appointment duration")
        return
      end
      check_time += 30.minutes
    end
    
    # Check for scheduling conflicts with other appointments
    conflicting_appointments = Appointment.where(
      service_provider_id: service_provider_id,
      status: 'scheduled' # Only consider scheduled appointments as conflicts
    ).where.not(id: id) # Exclude this appointment if it's being updated
     .where('(start_time <= ? AND end_time > ?) OR (start_time < ? AND end_time >= ?) OR (start_time >= ? AND end_time <= ?)',
            end_time, start_time, # Overlaps at the beginning
            end_time, start_time, # Overlaps at the end
            start_time, end_time) # Falls entirely within new appointment
    
    if conflicting_appointments.exists?
      errors.add(:base, "This time slot conflicts with another appointment for this service provider")
    end
  end
end 