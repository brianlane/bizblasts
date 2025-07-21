# frozen_string_literal: true

# Service for managing and calculating availability time slots
class AvailabilityService
  # Generate available time slots for a staff member on a specific date
  #
  # @param staff_member [StaffMember] the staff member to check
  # @param date [Date] the date for which to generate slots
  # @param service [Service, optional] the service being booked (to determine duration)
  # @param interval [Integer] the interval between slots in minutes (default: 30)
  # @param bust_cache [Boolean] whether to bypass the cache
  # @return [Array<Hash>] an array of available slot data with start_time and end_time
  def self.available_slots(staff_member, date, service = nil, interval: 30, bust_cache: false)
    return [] unless staff_member.active?
    
    # PERFORMANCE OPTIMIZATION: Skip past dates completely
    return [] if date < Date.current
    
    # PERFORMANCE OPTIMIZATION: Use more aggressive caching for future dates
    cache_duration = case
    when date == Date.current then 2.minutes  # Very short cache for today
    when date < Date.current + 3.days then 10.minutes  # Short cache for next few days
    else 1.hour  # Longer cache for distant future
    end
    
    # Include current hour in cache key for same-day slots to handle time progression
    time_component = date == Date.current ? Time.current.hour : 'static'
    
    # Include the business time zone in the cache key so slots are cached per-timezone.
    tz = staff_member.business&.time_zone.presence || 'UTC'
    tz_component = tz.parameterize(separator: '_')
    cache_key = "avail_#{staff_member.id}_#{date}_#{service&.id}_#{interval}_#{time_component}_tz_#{tz_component}"
    
    # Bust the cache if requested
    Rails.cache.delete(cache_key) if bust_cache
    
    Rails.cache.fetch(cache_key, expires_in: cache_duration) do
      raw_slots = compute_available_slots(staff_member, date, service, interval)
      filter_past_slots(raw_slots, date, staff_member.business)
    end
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
    
    # Check booking policy duration constraints
    business = staff_member.business
    policy = business&.booking_policy
    if policy
      duration_minutes = ((end_time - start_time) / 60.0).round
      
      # Check minimum duration
      if policy.min_duration_mins.present? && duration_minutes < policy.min_duration_mins
        Rails.logger.debug("FAILED: Booking duration (#{duration_minutes}m) less than policy minimum (#{policy.min_duration_mins}m)")
        return false
      end
      
      # Check maximum duration
      if policy.max_duration_mins.present? && duration_minutes > policy.max_duration_mins
        Rails.logger.debug("FAILED: Booking duration (#{duration_minutes}m) exceeds policy maximum (#{policy.max_duration_mins}m)")
        return false
      end
      
      # Check max daily bookings policy
      if policy.max_daily_bookings.present? && policy.max_daily_bookings > 0
        booking_date = start_time.to_date
        daily_bookings = check_daily_booking_limit(staff_member, booking_date, exclude_booking_id)
        
        if daily_bookings >= policy.max_daily_bookings
          Rails.logger.debug("FAILED: Max daily bookings (#{policy.max_daily_bookings}) reached for date #{booking_date}")
          return false
        end
      end
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
  # @param interval [Integer] the interval between slots in minutes (default: 30)
  # @param bust_cache [Boolean] whether to bypass the cache
  # @return [Hash] a hash with dates as keys and aggregated available slots as values
  def self.availability_calendar(staff_member:, start_date:, end_date:, service: nil, interval: 30, bust_cache: false)
    # Use a cache key based on unique parameters
    tz = staff_member.business&.time_zone.presence || 'UTC'
    
    # Do not automatically select a default service when none is provided.
    # When service is nil, slot generation will fall back to the generic
    # interval-based logic so that availability previews are not tied to an
    # arbitrary service duration. This prevents inaccurate slots when a staff
    # member offers multiple services with varying durations and also avoids
    # masking misconfiguration when the staff member has no active services.
    
    cache_key = ['availability_calendar', staff_member.id, start_date.to_s, end_date.to_s, service&.id, interval, tz].join('/')

    # Bust the cache if requested
    Rails.cache.delete(cache_key) if bust_cache

    Rails.cache.fetch(cache_key, expires_in: 15.minutes) do
      return {} unless staff_member.active?
      
      # Check for max advance days policy
      business = staff_member.business
      policy = business&.booking_policy
      if policy&.max_advance_days.present? && policy.max_advance_days > 0
        max_future_date = Time.current.to_date + policy.max_advance_days.days
        
        # Limit end_date to the max_advance_days
        if end_date > max_future_date
          Rails.logger.debug("Limiting end date from #{end_date} to #{max_future_date} due to max_advance_days policy")
          end_date = max_future_date
        end
        
        # If start_date is already beyond max_advance_days, return empty hash
        if start_date > max_future_date
          Rails.logger.debug("Start date #{start_date} exceeds maximum advance days (#{policy.max_advance_days})")
          return {}
        end
      end
      
      date_range = (start_date..end_date).to_a
      calendar_data = {}
      
      date_range.each do |date|
        # Pass the service object and cache-busting instruction
        calendar_data[date.to_s] = available_slots(staff_member, date, service, interval: interval, bust_cache: bust_cache)
      end
      
      calendar_data
    end
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

  def self.compute_available_slots(staff_member, date, service, interval)
    business = staff_member.business
    tz = business&.time_zone.presence || 'UTC'

    Time.use_zone(tz) do
      slot_duration = service&.duration || interval
      
      # Policy checks and step interval calculation
      policy = business&.booking_policy
      step_interval = if policy&.use_fixed_intervals?
                        policy.interval_mins&.clamp(5, 120) || 30
                      elsif policy
                        # When policy exists but fixed intervals is false, use service duration as step interval (original behavior)
                        (service&.duration || interval)&.clamp(5, 480) || interval
                      else
                        # No policy, use passed interval
                        interval&.clamp(5, 480) || interval
                      end
      
      time_slots = []
      if policy
        # Adjust to minimum duration
        if policy.min_duration_mins.present? && slot_duration < policy.min_duration_mins
          slot_duration = policy.min_duration_mins
        end
        # Exceed maximum duration
        if policy.max_duration_mins.present? && slot_duration > policy.max_duration_mins
          return []
        end
        # Max daily bookings
        if policy.max_daily_bookings.present? && policy.max_daily_bookings > 0
          current_bookings = check_daily_booking_limit(staff_member, date, nil)
          return [] if current_bookings >= policy.max_daily_bookings
        end
        # Max advance days
        if policy.max_advance_days.present? && policy.max_advance_days > 0
          max_date = Time.current.to_date + policy.max_advance_days.days
          return [] if date > max_date
        end
      end
      
      # Service capability
      # Check if staff member can perform this service
      if service.present? && !staff_member.services.include?(service)
        return []
      end
      
      # Determine intervals
      day_name = date.strftime('%A').downcase
      availability_data = staff_member.availability&.with_indifferent_access || {}
      intervals = if availability_data[:exceptions]&.key?(date.iso8601)
                    Array(availability_data[:exceptions][date.iso8601])
                  else
                    Array(availability_data[day_name])
                  end
      return [] unless intervals.any?
      
      intervals.each do |interval_data|
        start_str, end_str = interval_data['start'], interval_data['end']
        next unless start_str && end_str
        start_h, start_m = start_str.split(':').map(&:to_i)
        end_h, end_m = end_str.split(':').map(&:to_i)

        # Build start and end times in the business time-zone
        interval_start = Time.zone.local(date.year, date.month, date.day, start_h, start_m)
        interval_end   = Time.zone.local(date.year, date.month, date.day, end_h, end_m)

        # Handle overnight intervals (end before start)
        interval_end += 1.day if end_h < start_h

        # SPECIAL CASE: Treat an interval ending at 23:59 as inclusive of the very last
        # minute of the day so that services can finish exactly at midnight.
        # Without this, a 2-hour service starting at 22:00 would be excluded because
        # 22:00 + 120 mins = 00:00 which is > 23:59. By extending the end boundary by
        # one minute we effectively allow bookings that finish at 00:00.
        if end_h == 23 && end_m == 59
          interval_end += 1.minute
        end
        current = interval_start
        
        # The loop should check if the current time is a valid start time.
        # A valid start time is one where the service can be completed before the interval ends.
        last_possible_start_time = interval_end - slot_duration.minutes
        
        while current <= last_possible_start_time
          st = current
          en = current + slot_duration.minutes
          time_slots << { start_time: st, end_time: en } if check_full_availability(staff_member, st, en)
          current += step_interval.minutes
        end
      end
      
      filter_booked_slots(time_slots, staff_member, date, slot_duration)
    end
  end

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
    # Fetch policy and buffer time
    business = staff_member.business
    policy = business&.booking_policy
    buffer_minutes = policy&.buffer_time_mins || 0
    buffer_duration = buffer_minutes.minutes

    # Fetch bookings for the staff member that *might* conflict on the given date
    # Note: fetch_conflicting_bookings already considers buffer in its query range
    start_of_day_for_query = Time.zone.local(date.year, date.month, date.day).beginning_of_day
    end_of_day_for_query = Time.zone.local(date.year, date.month, date.day).end_of_day

    # Use the already modified fetch_conflicting_bookings for initial filtering
    existing_bookings = fetch_conflicting_bookings(staff_member, start_of_day_for_query, end_of_day_for_query)

    # Enhanced logging
    Rails.logger.debug("Checking #{slots.count} slots for conflicts with #{existing_bookings.count} existing bookings (buffer: #{buffer_minutes} mins)")
    if Rails.env.test?
      Rails.logger.debug("TEST DEBUG (Filter): Existing Bookings (with buffer): #{existing_bookings.map { |booking_data| { start_time: booking_data[1], end_time: booking_data[2] } }.inspect}")
      Rails.logger.debug("TEST DEBUG (Filter): Slots to check: #{slots.map { |s| s[:start_time].strftime('%H:%M') + '-' + s[:end_time].strftime('%H:%M') }.inspect}")
    end

    return slots if existing_bookings.empty?

    # Create a list of booked intervals including buffer times, sorted by start time
    # Note: existing_bookings is an array of arrays from pluck: [id, start_time, end_time, status]
    booked_intervals = existing_bookings.map do |booking_data|
      booking_id, start_time, end_time, status = booking_data
      {
        start_time: start_time,
        end_time: end_time + buffer_duration,
        booking_id: booking_id
      }
    end.sort_by { |interval| interval[:start_time] }

    filtered_slots = []
    booked_index = 0 # Pointer for the booked_intervals array

    slots.each do |slot|
      slot_start = slot[:start_time]
      slot_end = slot[:end_time]

      if Rails.env.test?
        Rails.logger.debug("TEST DEBUG (Filter Slot): Checking slot #{slot_start.strftime('%H:%M')}-#{slot_end.strftime('%H:%M')}")
      end

      conflicts = false
      booked_intervals.each do |booked_interval| # Iterate through all booked intervals
        booked_start = booked_interval[:start_time]
        booked_end = booked_interval[:end_time]

        if Rails.env.test?
          Rails.logger.debug("TEST DEBUG (Filter Conflict Check): Comparing slot #{slot_start.strftime('%H:%M')}-#{slot_end.strftime('%H:%M')} with booked #{booked_start.strftime('%H:%M')}-#{booked_end.strftime('%H:%M')} (Booking ID: #{booked_interval[:booking_id]})")
        end

        # Conflict check: (Booked interval starts before slot ends) AND (Booked interval ends after slot starts)
        if booked_start < slot_end && booked_end > slot_start
          Rails.logger.debug("CONFLICT: Slot #{slot_start.strftime('%H:%M')}-#{slot_end.strftime('%H:%M')} conflicts with booking #{booked_interval[:booking_id]} (incl. buffer)")
          conflicts = true
          break # No need to check further booked intervals for this slot
        end
      end

      unless conflicts
        Rails.logger.debug("AVAILABLE: Slot #{slot_start.strftime('%H:%M')}-#{slot_end.strftime('%H:%M')} has no conflicts")
        filtered_slots << slot
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
  
  # Helper to fetch bookings that potentially conflict with a given time range
  # Includes buffer time from BookingPolicy
  def self.fetch_conflicting_bookings(staff_member, start_time, end_time, exclude_booking_id = nil)
    business = staff_member.business
    buffer_time_mins = business.booking_policy&.buffer_time_mins || 0
    
    # PERFORMANCE OPTIMIZATION: Calculate time range once
    buffer_duration = buffer_time_mins.minutes
    query_start = start_time - buffer_duration
    query_end = end_time + buffer_duration
    
    # PERFORMANCE OPTIMIZATION: Use optimized query with indexes
    query = business.bookings
                    .joins(:staff_member)  # Ensure staff_member association is loaded
                    .where(staff_member_id: staff_member.id)
                    .where.not(status: ['cancelled', 'no_show'])
                    .where(
                      '(start_time < ? AND end_time > ?) OR (start_time < ? AND end_time > ?)',
                      query_end, query_start, query_start, query_end
                    )
    
    # Exclude specific booking if provided
    query = query.where.not(id: exclude_booking_id) if exclude_booking_id.present?
    
    # PERFORMANCE OPTIMIZATION: Use pluck to get only needed data instead of full objects
    query.pluck(:id, :start_time, :end_time, :status)
  end

  # Check the number of bookings for a staff member on a given date
  def self.check_daily_booking_limit(staff_member, date, exclude_booking_id = nil)
    query = Booking.where(
      staff_member_id: staff_member.id,
      start_time: date.beginning_of_day..date.end_of_day
    ).where.not(status: :cancelled)
    
    # Exclude specific booking if requested (for updates)
    query = query.where.not(id: exclude_booking_id) if exclude_booking_id
    
    query.count
  end

  # Filter out time slots that have already passed for today
  # Respects business time zone and minimum advance booking time policy
  #
  # @param slots [Array<Hash>] array of time slots with :start_time and :end_time
  # @param date [Date] the date being filtered
  # @param business [Business] the business context for time zone and policy
  # @return [Array<Hash>] filtered slots excluding past times
  def self.filter_past_slots(slots, date, business)
    return slots unless date == Date.current
    
    # Use business time zone for current time comparison
    current_time = if business.time_zone.present?
                     Time.current.in_time_zone(business.time_zone)
                   else
                     Time.current
                   end
    
    # Apply minimum advance booking time if policy exists
    policy = business.booking_policy
    if policy&.min_advance_mins.present? && policy.min_advance_mins > 0
      cutoff_time = current_time + policy.min_advance_mins.minutes
    else
      cutoff_time = current_time
    end
    
    Rails.logger.debug("Filtering past slots for #{date}: current time #{current_time.strftime('%H:%M')}, cutoff #{cutoff_time.strftime('%H:%M')}")
    
    filtered_slots = slots.reject { |slot| slot[:start_time] <= cutoff_time }
    
    Rails.logger.debug("Past time filtering: #{slots.count} original slots, #{filtered_slots.count} after filtering")
    
    filtered_slots
  end
end