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

  # Customer-friendly policy display methods
  def customer_friendly_cancellation_policy
    return "Flexible cancellation - cancel anytime" if cancellation_window_mins.blank?
    
    case cancellation_window_mins
    when 0
      "Cancel anytime before your appointment"
    when 1..60
      "Cancel up to #{cancellation_window_mins} #{'minute'.pluralize(cancellation_window_mins)} before your appointment"
    when 61..1439
      hours = (cancellation_window_mins / 60.0)
      if hours == hours.to_i
        "Cancel up to #{hours.to_i} #{'hour'.pluralize(hours.to_i)} before your appointment"
      else
        "Cancel up to #{hours.round(1)} hours before your appointment"
      end
    else
      days = (cancellation_window_mins / 1440.0)
      if days == days.to_i
        "Cancel up to #{days.to_i} #{'day'.pluralize(days.to_i)} before your appointment"
      else
        "Cancel up to #{days.round(1)} days before your appointment"
      end
    end
  end

  def customer_friendly_advance_booking_policy
    return nil if min_advance_mins.blank? || min_advance_mins <= 0
    
    case min_advance_mins
    when 1..60
      "Book at least #{min_advance_mins} #{'minute'.pluralize(min_advance_mins)} in advance"
    when 61..1439
      hours = (min_advance_mins / 60.0)
      if hours == hours.to_i
        "Book at least #{hours.to_i} #{'hour'.pluralize(hours.to_i)} in advance"
      else
        "Book at least #{hours.round(1)} hours in advance"
      end
    else
      days = (min_advance_mins / 1440.0)
      if days == days.to_i
        "Book at least #{days.to_i} #{'day'.pluralize(days.to_i)} in advance"
      else
        "Book at least #{days.round(1)} days in advance"
      end
    end
  end

  def customer_friendly_booking_window_policy
    return nil if max_advance_days.blank?
    
    "Book up to #{max_advance_days} #{'day'.pluralize(max_advance_days)} in advance"
  end

  def has_customer_visible_policies?
    cancellation_window_mins.present? || 
    (min_advance_mins.present? && min_advance_mins > 0) || 
    max_advance_days.present?
  end

  def cancellation_policy_icon
    return "🕐" if cancellation_window_mins.blank?
    
    case cancellation_window_mins
    when 0..60
      "⏰"
    when 61..1439
      "🕐"
    else
      "📅"
    end
  end

  def policy_summary_for_customers
    policies = []
    
    if cancellation_window_mins.present?
      policies << customer_friendly_cancellation_policy
    else
      policies << "Flexible cancellation policy"
    end
    
    advance_policy = customer_friendly_advance_booking_policy
    policies << advance_policy if advance_policy
    
    window_policy = customer_friendly_booking_window_policy
    policies << window_policy if window_policy
    
    policies
  end

  def cancellation_example_for_customers
    return nil if cancellation_window_mins.blank?
    
    example_time = Time.current + 2.days + 14.hours # Example: day after tomorrow at 2 PM
    cutoff_time = example_time - cancellation_window_mins.minutes
    
    "Cancel by #{cutoff_time.strftime('%A at %l:%M %p')} " \
    "(for appointment booked #{example_time.strftime('%A at %l:%M %p')})"
  end

  # Business manager override methods
  def allows_manager_override?
    # Business managers can always override cancellation windows
    true
  end

  def cancellation_allowed_for?(user, booking)
    # Allow cancellation if user is a manager or staff member
    return true if user&.manager? || user&.staff?
    
    # Apply normal policy for clients
    return true if cancellation_window_mins.blank?
    
    cancellation_deadline = booking.start_time - cancellation_window_mins.minutes
    Time.current <= cancellation_deadline
  end

  # Check if a specific user can cancel a booking
  def user_can_cancel?(user, booking)
    # Business managers and staff can always cancel
    return true if user&.manager? || user&.staff?
    
    # Check if booking is in the past
    return false if booking.start_time < Time.current
    
    # Check cancellation window for regular users
    cancellation_allowed_for?(user, booking)
  end

  private

  def min_not_greater_than_max
    return if min_duration_mins.nil? || max_duration_mins.nil?
    if min_duration_mins > max_duration_mins
      errors.add(:min_duration_mins, 'cannot be greater than maximum duration')
    end
  end
end 