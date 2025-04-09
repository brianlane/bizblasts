# frozen_string_literal: true

# Service for managing and calculating availability time slots
class AvailabilityService
  # Generate available time slots for a staff member on a specific date
  #
  # @param staff_member [StaffMember] the staff member to check
  # @param date [Date] the date for which to generate slots
  # @param service [Service, optional] the service being booked (to determine duration)
  # @param interval [Integer] the interval between slots in minutes (default: 30)
  # @return [Array<Time>] an array of available start times
  def self.available_slots(staff_member, date, service = nil, interval: 30)
    return [] unless staff_member.active?

    duration = service&.duration || interval # Use service duration or default interval
    time_slots = []
    # Ensure start/end of day are in the correct Time.zone
    start_of_day = Time.zone.local(date.year, date.month, date.day).beginning_of_day
    end_of_day = Time.zone.local(date.year, date.month, date.day).end_of_day
    current_time = start_of_day

    while current_time + duration.minutes <= end_of_day
      # Filter slots based on staff member availability
      # Check if the staff member is available for the *entire* duration of the slot
      start_slot_time = current_time
      end_slot_time = current_time + duration.minutes

      # Use the check_full_availability helper method
      if check_full_availability(staff_member, start_slot_time, end_slot_time)
        time_slots << start_slot_time
      end

      current_time += interval.minutes
    end

    # Remove slots that conflict with existing bookings
    available_slots = filter_booked_slots(time_slots, staff_member, date, duration)

    available_slots
  end

  # Check if a staff member is available for a specific time range
  #
  # @param staff_member [StaffMember] the staff member
  # @param start_time [Time] the start of the time range
  # @param end_time [Time] the end of the time range
  # @return [Boolean] true if the staff member is available, false otherwise
  def self.is_available?(staff_member:, start_time:, end_time:)
    # Check active status first
    return false unless staff_member.active?
    # Use the detailed check_full_availability method
    check_full_availability(staff_member, start_time, end_time)
  end


  private

  # Check if a staff member is available for the entire duration
  def self.check_full_availability(staff_member, start_time, end_time)
    # Check availability in small increments (e.g., 5 minutes) within the interval
    return false unless staff_member.active? # Check active status first
    return false unless staff_member.available_at?(start_time)
    
    check_time = start_time + 5.minutes
    while check_time < end_time
      return false unless staff_member.available_at?(check_time)
      check_time += 5.minutes
    end
    # Also check the very end time boundary, as available_at? uses '< end_time'
    # This ensures availability *up to* the end time.
    return false unless staff_member.available_at?(end_time - 1.minute)
    true
  end

  # Filter out time slots that overlap with existing bookings
  def self.filter_booked_slots(slots, staff_member, date, duration)
    # Fetch bookings for the staff member that overlap the given date
    # Ensure start/end of day for query are also in the correct Time.zone
    start_of_day_for_query = Time.zone.local(date.year, date.month, date.day).beginning_of_day
    end_of_day_for_query = Time.zone.local(date.year, date.month, date.day).end_of_day
    # Revert to pre-fetching bookings overlapping the day
    existing_bookings = Booking.where(
      staff_member_id: staff_member.id
    ).where.not(
      status: [:cancelled, :rejected]
    ).where(
      "bookings.start_time < ? AND bookings.end_time > ?", end_of_day_for_query, start_of_day_for_query
    )

    return slots if existing_bookings.empty?

    slots.reject do |slot_start_time_local|
      slot_end_time_local = slot_start_time_local + duration.minutes

      # Convert slot times to UTC for comparison
      slot_start_utc = slot_start_time_local.utc
      slot_end_utc = slot_end_time_local.utc

      existing_bookings.any? do |booking| # booking times are already UTC
        # Compare UTC times
        booking.start_time < slot_end_utc && booking.end_time > slot_start_utc
      end
    end
  end
end 