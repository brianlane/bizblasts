# frozen_string_literal: true

# Concern for handling booking validations
module BookingValidations
  extend ActiveSupport::Concern

  included do
    # Common validations for bookings
    validates :service, presence: true
    validates :tenant_customer, presence: true
    validates :staff_member, presence: true
    validates :start_time, presence: true
    validates :end_time, presence: true
    validates :original_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :discount_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    
    validate :end_time_after_start_time
    validate :no_overlapping_bookings, on: :create
  end
  
  # Calculate booking duration in minutes
  def duration
    # Ensure duration is calculated as an integer (minutes)
    ((end_time - start_time) / 60.0).round
  end
  
  private
  
  # Validate end_time is after start_time
  def end_time_after_start_time
    return if end_time.blank? || start_time.blank?
    
    if end_time <= start_time
      errors.add(:end_time, "must be after the start time")
    end
  end
  
  # Validate booking doesn't overlap with other bookings for the same staff member
  def no_overlapping_bookings
    return if start_time.blank? || end_time.blank? || staff_member_id.blank?
    
    overlapping = self.class
                    .where(staff_member_id: staff_member_id)
                    .where.not(status: :cancelled)
                    .where.not(id: id)
                    .where("start_time < ? AND end_time > ?", end_time, start_time)
    
    if overlapping.exists?
      errors.add(:base, "Booking conflicts with another existing booking for this staff member")
    end
  end
end 