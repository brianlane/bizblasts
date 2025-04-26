# frozen_string_literal: true

# Service for managing and calculating availability time slots
class AvailabilityService
  # Generate available time slots for a staff member on a specific date
  #
  # @param staff_member [StaffMember] the staff member to check
  # @param date [Date] the date for which to generate slots
  # @param service [Service, optional] the service being booked (to determine duration)
  # @param interval [Integer] the interval between slots in minutes (default: 30)
  # @return [Array<Hash>] an array of available slot data with start_time and end_time
  def self.available_slots(staff_member, date, service = nil, interval: 30)
    return [] unless staff_member.active?

    duration = service&.duration || interval # Use service duration or default interval
    time_slots = []
    
    # Enhanced logging
    Rails.logger.debug("=== AVAILABILITY DEBUG ===")
    Rails.logger.debug("Generating available slots for: #{staff_member.name}, Date: #{date}, Service: #{service&.name}, Duration: #{duration} minutes")
    
    # Check if staff member can perform this service
    if service.present? && !staff_member.services.include?(service)
      Rails.logger.debug("BLOCKING FACTOR: Staff member cannot perform this service")
      return []
    end
    
    # Get the day's availability intervals from staff member's schedule
    day_name = date.strftime('%A').downcase
    availability_data = staff_member.availability&.with_indifferent_access || {}
    
    Rails.logger.debug("Day name: #{day_name}")
    Rails.logger.debug("Availability data: #{availability_data.inspect}")
    
    # Check for date-specific exceptions first, then fall back to regular schedule
    intervals = if availability_data[:exceptions]&.key?(date.iso8601)
      availability_data[:exceptions][date.iso8601]
    else
      availability_data[day_name]
    end
    
    Rails.logger.debug("Intervals for #{day_name}: #{intervals.inspect}")
    
    return [] unless intervals.is_a?(Array) && intervals.any?
    
    # Generate slots for each availability interval
    intervals.each do |interval_data|
      start_time_str = interval_data['start']
      end_time_str = interval_data['end']
      
      next unless start_time_str && end_time_str
      
      # Parse the time strings into Time objects for the given date
      begin
        start_hour, start_minute = start_time_str.split(':').map(&:to_i)
        end_hour, end_minute = end_time_str.split(':').map(&:to_i)
        
        # Create times in the business's time zone
        interval_start = Time.zone.local(date.year, date.month, date.day, start_hour, start_minute)
        interval_end = Time.zone.local(date.year, date.month, date.day, end_hour, end_minute)
        
        # If end time is before start time (e.g., "23:00" to "02:00"), adjust end time to next day
        if end_hour < start_hour
          interval_end = interval_end + 1.day
        end
        
        current_time = interval_start
        
        Rails.logger.debug("Processing interval: #{interval_start.strftime('%H:%M')} to #{interval_end.strftime('%H:%M')}")

        # Only filter future times in production environment
        unless Rails.env.test?
          current_time = [current_time, Time.current.beginning_of_hour + interval.minutes].max
        end

        while current_time + duration.minutes <= interval_end
          start_slot_time = current_time
          end_slot_time = current_time + duration.minutes

          # Check full availability for the slot
          if check_full_availability(staff_member, start_slot_time, end_slot_time)
            time_slots << {
              start_time: start_slot_time,
              end_time: end_slot_time
            }
          end

          current_time += interval.minutes
        end
      rescue ArgumentError => e
        Rails.logger.error("Invalid time format in staff availability: #{e.message}")
        next
      end
    end
    
    Rails.logger.debug("Generated #{time_slots.count} initial time slots before filtering")

    # Remove slots that conflict with existing bookings
    available_slots = filter_booked_slots(time_slots, staff_member, date, duration)
    
    Rails.logger.debug("Final available slots: #{available_slots.count}")

    available_slots
  end

  # Check if a staff member is available for a specific time range
  #
  # @param staff_member [StaffMember] the staff member
  # @param start_time [Time] the start of the time range
  # @param end_time [Time] the end of the time range
  # @param service [Service, optional] the service being checked for (can apply service restrictions)
  # @param exclude_booking_id [Integer, nil] ID of booking to exclude from conflict check
  # @return [Boolean] true if the staff member is available, false otherwise
  def self.is_available?(staff_member:, start_time:, end_time:, service: nil, exclude_booking_id: nil)
    # Check active status first
    return false unless staff_member.active?
    
    # Check if staff member can perform this service if provided
    if service.present? && !staff_member.services.include?(service)
      return false
    end
    
    # Use the detailed check_full_availability method
    return false unless check_full_availability(staff_member, start_time, end_time)
    
    # Check if the slot conflicts with existing bookings
    !booking_conflict_exists?(staff_member, start_time, end_time, exclude_booking_id)
  end
  
  # Get availability calendar data for a date range
  #
  # @param staff_member [StaffMember] the staff member
  # @param start_date [Date] the start date of the range
  # @param end_date [Date] the end date of the range
  # @param service [Service, optional] the service being booked
  # @return [Hash] a hash with dates as keys and available slots as values
  def self.availability_calendar(staff_member:, start_date:, end_date:, service: nil, interval: 30)
    return {} unless staff_member.active?
    
    date_range = (start_date..end_date).to_a
    calendar_data = {}
    
    date_range.each do |date|
      calendar_data[date.to_s] = available_slots(staff_member, date, service, interval: interval)
    end
    
    calendar_data
  end

  # Get staff members available for a service on a specific date and time
  #
  # @param service [Service] the service
  # @param date [Date] the date
  # @param start_time [Time] the start time
  # @param end_time [Time] the end time (calculated from service duration if nil)
  # @return [Array<StaffMember>] an array of available staff members
  def self.available_staff_for_service(service:, date:, start_time:, end_time: nil)
    return [] unless service.active?
    
    # Calculate end time based on service duration if not provided
    end_time ||= start_time + service.duration.minutes
    
    # Get all staff members who can perform this service
    staff_members = service.staff_members.active
    
    # Filter to only those available at the given time
    staff_members.select do |staff_member|
      is_available?(
        staff_member: staff_member,
        start_time: start_time,
        end_time: end_time,
        service: service
      )
    end
  end

  private

  # Check if a staff member is available for the entire duration
  def self.check_full_availability(staff_member, start_time, end_time)
    # Check availability in small increments (e.g., 5 minutes) within the interval
    return false unless staff_member.active? # Check active status first
    
    # Debug
    Rails.logger.debug("Checking full availability for slot: #{start_time.strftime('%H:%M')} - #{end_time.strftime('%H:%M')}")
    
    unless staff_member.available_at?(start_time)
      Rails.logger.debug("FAILED: Staff not available at start time: #{start_time.strftime('%H:%M')}")
      return false
    end
    
    check_time = start_time + 5.minutes
    while check_time < end_time
      unless staff_member.available_at?(check_time)
        Rails.logger.debug("FAILED: Staff not available at check time: #{check_time.strftime('%H:%M')}")
        return false
      end
      check_time += 5.minutes
    end
    # Also check the very end time boundary, as available_at? uses '< end_time'
    # This ensures availability *up to* the end time.
    unless staff_member.available_at?(end_time - 1.minute)
      Rails.logger.debug("FAILED: Staff not available at end time: #{(end_time - 1.minute).strftime('%H:%M')}")
      return false
    end
    
    Rails.logger.debug("SUCCESS: Staff fully available for slot: #{start_time.strftime('%H:%M')} - #{end_time.strftime('%H:%M')}")
    true
  end

  # Filter out time slots that overlap with existing bookings
  def self.filter_booked_slots(slots, staff_member, date, duration)
    # Fetch bookings for the staff member that overlap the given date
    # Ensure start/end of day for query are also in the correct Time.zone
    start_of_day_for_query = Time.zone.local(date.year, date.month, date.day).beginning_of_day
    end_of_day_for_query = Time.zone.local(date.year, date.month, date.day).end_of_day
    
    existing_bookings = fetch_conflicting_bookings(staff_member, start_of_day_for_query, end_of_day_for_query)
    
    # Enhanced logging
    Rails.logger.debug("Checking #{slots.count} slots for conflicts with #{existing_bookings.count} existing bookings")
    
    if existing_bookings.any?
      Rails.logger.debug("Existing bookings for #{date}:")
      existing_bookings.each do |booking|
        Rails.logger.debug("  - #{booking.id}: #{booking.start_time.strftime('%H:%M')} - #{booking.end_time.strftime('%H:%M')} (#{booking.status})")
      end
    end
    
    return slots if existing_bookings.empty?

    filtered_slots = slots.reject do |slot|
      # Check if any booking conflicts with this slot
      conflicts = existing_bookings.any? do |booking|
        # A conflict exists if the booking overlaps with the slot
        # (booking starts before slot ends) AND (booking ends after slot starts)
        conflict = booking.start_time < slot[:end_time] && booking.end_time > slot[:start_time]
        if conflict
          Rails.logger.debug("CONFLICT: Slot #{slot[:start_time].strftime('%H:%M')}-#{slot[:end_time].strftime('%H:%M')} conflicts with booking #{booking.id}")
        end
        conflict
      end
      
      if conflicts
        true # Reject this slot
      else
        Rails.logger.debug("AVAILABLE: Slot #{slot[:start_time].strftime('%H:%M')}-#{slot[:end_time].strftime('%H:%M')} has no conflicts")
        false # Keep this slot
      end
    end
    
    Rails.logger.debug("For date #{date}: Original slots: #{slots.count}, After filtering: #{filtered_slots.count}")
    
    filtered_slots
  end
  
  # Check if a booking conflict exists for a specific time range
  def self.booking_conflict_exists?(staff_member, start_time, end_time, exclude_booking_id = nil)
    existing_bookings = fetch_conflicting_bookings(staff_member, start_time, end_time, exclude_booking_id)
    existing_bookings.any?
  end
  
  # Fetch bookings that would conflict with the given time range
  def self.fetch_conflicting_bookings(staff_member, start_time, end_time, exclude_booking_id = nil)
    query = Booking.where(
      staff_member_id: staff_member.id
    ).where.not(
      status: [:cancelled, :rejected]
    ).where(
      "bookings.start_time < ? AND bookings.end_time > ?", end_time, start_time
    )
    
    # Exclude a specific booking if requested (useful for editing a booking)
    query = query.where.not(id: exclude_booking_id) if exclude_booking_id.present?
    
    query
  end
end