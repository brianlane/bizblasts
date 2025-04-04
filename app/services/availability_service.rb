# frozen_string_literal: true

# Service for managing and calculating availability time slots
class AvailabilityService
  # Generate available time slots for a service provider on a specific date
  # 
  # @param service_provider [ServiceProvider] the service provider to check
  # @param date [Date] the date to check availability for
  # @param service [Service] (optional) the service being booked
  # @param interval [Integer] (optional) the interval in minutes between slots, defaults to 30
  # @return [Array<Hash>] array of available time slots with :start_time and :end_time keys
  def self.available_slots(service_provider, date, service = nil, interval: 30)
    return [] unless service_provider.active?
    
    # Get the service duration in minutes (use correct attribute name)
    duration = service&.duration || interval
    
    # Generate all possible time slots for the day at the given interval
    all_slots = generate_time_slots(date, interval)
    
    # Filter slots based on service provider availability
    available_slots = all_slots.select do |slot|
      start_time = Time.zone.parse("#{date.iso8601} #{slot[:time]}")
      end_time = start_time + duration.minutes
      
      # Check if entire appointment duration would be within availability
      check_full_availability(service_provider, start_time, end_time)
    end
    
    # Now filter out slots that conflict with existing appointments
    available_slots = filter_booked_slots(available_slots, service_provider, date, duration)
    
    # Convert available times to full timestamps
    available_slots.map do |slot|
      start_time = Time.zone.parse("#{date.iso8601} #{slot[:time]}")
      end_time = start_time + duration.minutes
      {
        start_time: start_time,
        end_time: end_time,
        formatted_time: start_time.strftime('%l:%M %p').strip # For display purposes
      }
    end
  end
  
  private
  
  # Generate all possible time slots for a day at given interval
  def self.generate_time_slots(date, interval)
    slots = []
    
    # Start at 0:00 and go until 23:59
    current_time = Tod::TimeOfDay.new(0, 0)
    end_of_day = Tod::TimeOfDay.new(23, 59)
    
    while current_time < end_of_day
      slots << { time: current_time.strftime('%H:%M') }
      current_time = current_time + interval.minutes
    end
    
    slots
  end
  
  # Check if a service provider is available for the entire duration
  def self.check_full_availability(service_provider, start_time, end_time)
    # Restore original logic
    return false unless service_provider.active? # Check active status first
    return false unless service_provider.available_at?(start_time)
    
    check_time = start_time + 15.minutes
    while check_time < end_time
      return false unless service_provider.available_at?(check_time)
      check_time += 15.minutes
    end
    
    true
  end
  
  # Filter out slots that conflict with existing appointments
  def self.filter_booked_slots(slots, service_provider, date, duration)
    date_start = date.beginning_of_day
    date_end = date.end_of_day
    
    # Get all confirmed bookings for this provider on this date
    existing_bookings = Booking.where(
      staff_member_id: service_provider.id, 
      status: :confirmed # Use the correct enum symbol
    ).where('start_time >= ? AND start_time <= ?', date_start, date_end)
    
    # Create time ranges that are already booked
    booked_ranges = existing_bookings.map do |booking|
      # Add a small buffer before and after (e.g., 5 minutes)
      buffer = 5.minutes
      [booking.start_time - buffer, booking.end_time + buffer]
    end
    
    # Filter available slots to exclude those overlapping with booked times
    slots.reject do |slot|
      start_time = Time.zone.parse("#{date.iso8601} #{slot[:time]}")
      end_time = start_time + duration.minutes
      
      # Check if this slot overlaps with any booked range
      booked_ranges.any? do |booked_start, booked_end|
        (start_time >= booked_start && start_time < booked_end) || # Slot starts during a booking
        (end_time > booked_start && end_time <= booked_end) || # Slot ends during a booking
        (start_time <= booked_start && end_time >= booked_end) # Slot completely contains a booking
      end
    end
  end
end 