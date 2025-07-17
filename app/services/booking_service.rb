# frozen_string_literal: true

# Service for shared booking functionality across base domain and subdomains
class BookingService
  # Generate calendar data for a date range for a specific service (all staff)
  #
  # @param service [Service] the service being booked
  # @param date [Date] the center date for the calendar
  # @param tenant [Business, nil] the tenant/business context (optional)
  # @param start_date [Date, nil] the start date of the range (optional)
  # @param end_date [Date, nil] the end date of the range (optional)
  # @return [Hash] calendar data with dates as keys and aggregated available slots as values
  def self.generate_calendar_data(service:, date:, tenant: nil, start_date: nil, end_date: nil, interval: nil)
    return {} unless service && date
    
    staff_members = service.staff_members.active
    return {} if staff_members.empty?

    # Determine the date range for the calendar
    range_start = start_date || date.beginning_of_month
    range_end   = end_date   || date.end_of_month
    
    # PERFORMANCE OPTIMIZATION: Use bulk caching and parallel processing for multiple staff
    tz = tenant&.time_zone.presence || service.business&.time_zone.presence || 'UTC'
    slot_interval = interval || service.duration
    cache_key = "calendar_data_#{service.id}_#{range_start}_#{range_end}_#{staff_members.pluck(:id).join(',')}_interval_#{slot_interval}_tz_#{tz.parameterize(separator: '_')}"
    
    Rails.cache.fetch(cache_key, expires_in: 30.minutes) do
      calendar_data = {}
      date_range = (range_start..range_end).to_a
      
      # PERFORMANCE OPTIMIZATION: Process dates in batches to avoid memory issues
      date_range.each_slice(7) do |date_batch|
        date_batch.each do |current_date|
          # Skip past dates entirely
          next if current_date < Date.current
          
          daily_aggregated_slots = []
          
          # PERFORMANCE OPTIMIZATION: Use more efficient staff processing
          staff_members.find_each do |staff_member|
            available_slots = AvailabilityService.available_slots(
              staff_member,
              current_date,
              service,
              interval: slot_interval
            )
            
            # Add staff info to each slot
            enriched_slots = available_slots.map do |slot|
              slot.merge(staff_member_id: staff_member.id, staff_member_name: staff_member.name)
            end
            daily_aggregated_slots.concat(enriched_slots)
          end
          
          # Sort slots by start time for the day
          calendar_data[current_date.to_s] = daily_aggregated_slots.sort_by { |slot| slot[:start_time] }
        end
      end
      
      calendar_data
    end
  end
  
  # Fetch available slots for a specific date for a service (all staff)
  #
  # @param service [Service] the service being booked
  # @param date [Date] the date to check
  # @param interval [Integer] the interval between slots in minutes
  # @param tenant [Business, nil] the tenant/business context (optional)
  # @return [Array<Hash>] array of available slot data including staff info
  def self.fetch_available_slots(service:, date:, interval: 30, tenant: nil)
    return [] unless service && date
    
    staff_members = service.staff_members.active
    return [] if staff_members.empty?

    all_available_slots = []
    staff_members.each do |staff_member|
      available_slots = AvailabilityService.available_slots(
        staff_member, 
        date, 
        service, 
        interval: interval
      )
      # Add staff info to each slot
      enriched_slots = available_slots.map do |slot|
        slot.merge(staff_member_id: staff_member.id, staff_member_name: staff_member.name)
      end
      all_available_slots.concat(enriched_slots)
    end
    
    # Sort final list by start time
    all_available_slots.sort_by { |slot| slot[:start_time] }
  end
  
  # Fetch staff availability for a service on a specific date
  #
  # @param service [Service] the service
  # @param date [Date] the date to check
  # @param tenant [Business, nil] the tenant/business context (optional)
  # @return [Hash] staff_id => available_slots mapping
  def self.fetch_staff_availability(service:, date:, tenant: nil)
    return {} unless service && date
    
    # Find available staff for this service on this date
    staff_members = service.staff_members.active
    
    # Get availability calendar data for each staff member
    staff_availability = {}
    
    staff_members.each do |staff_member|
      staff_availability[staff_member.id] = AvailabilityService.available_slots(
        staff_member,
        date,
        service
      )
    end
    
    staff_availability
  end
  
  # Create a new booking with proper validation and error handling
  #
  # @param booking_params [Hash] parameters for creating the booking
  # @param tenant [Business, nil] the tenant/business context (optional)
  # @return [Array<Booking, Object>] the booking object and any errors
  def self.create_booking(booking_params, tenant = nil)
    # Use the existing BookingManager implementation
    BookingManager.create_booking(booking_params, tenant)
  end
  
  # Update an existing booking
  #
  # @param booking [Booking] the booking to update
  # @param booking_params [Hash] parameters for updating the booking
  # @return [Array<Booking, Object>] the updated booking and any errors
  def self.update_booking(booking, booking_params)
    # Use the existing BookingManager implementation
    BookingManager.update_booking(booking, booking_params)
  end
  
  # Cancel a booking
  #
  # @param booking [Booking] the booking to cancel
  # @param reason [String, nil] reason for cancellation
  # @param notify [Boolean] whether to notify affected parties
  # @return [Array<Boolean, String>] success status and error message (if any)
  def self.cancel_booking(booking, reason = nil, notify = true)
    # Use the existing BookingManager implementation
    BookingManager.cancel_booking(booking, reason, notify)
  end
  
  # Check if a booking slot is available
  #
  # @param staff_member [StaffMember] the staff member to check
  # @param start_time [Time] the start time of the slot
  # @param end_time [Time] the end time of the slot
  # @param exclude_booking_id [Integer, nil] booking ID to exclude from conflict check
  # @return [Boolean] true if the slot is available, false otherwise
  def self.slot_available?(staff_member:, start_time:, end_time:, exclude_booking_id: nil)
    AvailabilityService.is_available?(
      staff_member: staff_member,
      start_time: start_time,
      end_time: end_time,
      exclude_booking_id: exclude_booking_id
    )
  end
end 