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
    validate :check_max_advance_days_policy, on: :create
    validate :check_max_daily_bookings_policy, on: :create
    validate :check_min_duration_policy, on: :create
    validate :check_max_duration_policy, on: :create
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
  
  # Validate booking doesn't overlap with other bookings for the same staff member, considering buffer time
  def no_overlapping_bookings
    return if start_time.blank? || end_time.blank? || staff_member_id.blank? || business.blank?
    
    # Fetch buffer time from policy, default to 0 if not set
    policy = business.booking_policy
    buffer_minutes = policy&.buffer_time_mins || 0
    buffer_duration = buffer_minutes.minutes
    
    # Adjust the time window for the new booking to include buffer
    effective_start_time = start_time
    effective_end_time = end_time + buffer_duration
    
    # Find existing bookings that conflict with the effective window
    overlapping_bookings = self.class
                           .where(staff_member_id: staff_member_id)
                           .where.not(status: :cancelled)
                           .where.not(id: id)
                           # Existing booking starts before new one ends AND Existing booking ends after new one starts
                           # (Adjusted to consider buffer)
                           .where("start_time < :effective_end_time AND (end_time + make_interval(mins := :buffer_minutes)) > :effective_start_time",
                                  { 
                                    effective_end_time: effective_end_time, 
                                    effective_start_time: effective_start_time, 
                                    buffer_minutes: buffer_minutes 
                                  })
    
    if overlapping_bookings.exists?
      errors.add(:base, "Booking conflicts with another existing booking for this staff member, considering buffer time")
    end
  end

  # Validate booking is not too far in the future based on policy
  def check_max_advance_days_policy
    return if start_time.blank?
    policy = business&.booking_policy
    return if policy.blank? || policy.max_advance_days.blank?
    
    max_days = policy.max_advance_days
    if start_time.to_date > (Time.current.to_date + max_days.days)
      errors.add(:start_time, "cannot be more than #{max_days} #{'day'.pluralize(max_days)} in advance")
    end
  end

  # Validate booking does not exceed max daily limit for the staff member based on policy
  def check_max_daily_bookings_policy
    return if start_time.blank? || staff_member_id.blank?
    policy = business&.booking_policy
    return if policy.blank? || policy.max_daily_bookings.blank?

    max_bookings = policy.max_daily_bookings
    booking_date = start_time.to_date
    # Count existing, non-cancelled bookings for the staff member on the same day
    existing_bookings_count = self.class
                               .where(staff_member_id: staff_member_id)
                               .where(start_time: booking_date.all_day)
                               .where.not(status: :cancelled)
                               .where.not(id: id)
                               .count

    if existing_bookings_count >= max_bookings
      errors.add(:base, "Maximum daily bookings (#{max_bookings}) reached for this staff member on #{booking_date.strftime('%Y-%m-%d')}")
    end
  end
  
  # Validate booking meets minimum duration requirement
  def check_min_duration_policy
    return if start_time.blank? || end_time.blank? || business.blank?
    
    policy = business.booking_policy
    return if policy.blank? || policy.min_duration_mins.blank?
    
    min_duration = policy.min_duration_mins
    current_duration = duration
    
    if current_duration < min_duration
      errors.add(:base, "Booking duration (#{current_duration} minutes) cannot be less than the minimum required duration (#{min_duration} minutes)")
    end
  end
  
  # Validate booking does not exceed maximum duration requirement
  def check_max_duration_policy
    return if start_time.blank? || end_time.blank? || business.blank?
    
    policy = business.booking_policy
    return if policy.blank? || policy.max_duration_mins.blank?
    
    max_duration = policy.max_duration_mins
    current_duration = duration
    
    if current_duration > max_duration
      errors.add(:base, "Booking duration (#{current_duration} minutes) cannot exceed the maximum allowed duration (#{max_duration} minutes)")
    end
  end
end 