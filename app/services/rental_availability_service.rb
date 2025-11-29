# frozen_string_literal: true

# Service for managing rental availability
# Follows patterns from AvailabilityService but adapted for rental products
class RentalAvailabilityService
  # Constants
  MAX_CALENDAR_DAYS = 90  # Maximum date range for availability calendar
  CACHE_EXPIRY_MINUTES = 15  # Cache expiration time
  DEFAULT_REMINDER_HOURS = 24  # Default hours before rental to send reminder

  # ============================================
  # CLASS METHODS
  # ============================================

  # Find available rentals for a business within a time period
  #
  # @param business [Business] the business to search
  # @param start_time [Time] start of rental period
  # @param end_time [Time] end of rental period
  # @param rental_category [String, nil] optional filter by rental category
  # @param location_id [Integer, nil] optional filter by location
  # @param quantity [Integer] required quantity (default: 1)
  # @return [Array<Product>] available rental products
  def self.available_rentals(business:, start_time:, end_time:, rental_category: nil, location_id: nil, quantity: 1)
    rentals = business.products.rentals.active.positioned
    rentals = rentals.where(rental_category: rental_category) if rental_category.present?
    rentals = rentals.where(location_id: location_id) if location_id.present?
    
    rentals.select do |rental|
      rental.rental_available_for?(start_time, end_time, quantity: quantity)
    end
  end
  
  # Check if a specific rental is available
  #
  # @param rental [Product] the rental product
  # @param start_time [Time] start of rental period
  # @param end_time [Time] end of rental period
  # @param quantity [Integer] requested quantity
  # @param exclude_booking_id [Integer, nil] booking ID to exclude (for updates)
  # @return [Boolean] true if available
  def self.available?(rental:, start_time:, end_time:, quantity: 1, exclude_booking_id: nil)
    return false unless rental.rental?
    return false unless rental.active?
    
    # Check duration constraints
    return false unless rental.valid_rental_duration?(start_time, end_time)
    
    # Check availability
    rental.rental_available_for?(start_time, end_time, quantity: quantity, exclude_booking_id: exclude_booking_id)
  end
  
  # Get availability calendar for a rental
  #
  # @param rental [Product] the rental product
  # @param start_date [Date] start of date range
  # @param end_date [Date] end of date range
  # @param bust_cache [Boolean] whether to bypass cache
  # @return [Hash] calendar data with availability per day
  def self.availability_calendar(rental:, start_date:, end_date:, bust_cache: false)
    return {} unless rental.rental?

    # Validate date range
    days = (end_date - start_date).to_i
    if days > MAX_CALENDAR_DAYS
      raise ArgumentError, "Date range cannot exceed #{MAX_CALENDAR_DAYS} days (requested: #{days} days)"
    end

    if days < 0
      raise ArgumentError, "End date must be after start date"
    end

    # Build cache key
    tz = rental.business&.time_zone.presence || 'UTC'
    cache_key = build_calendar_cache_key(
      rental: rental,
      start_date: start_date,
      end_date: end_date,
      tz: tz
    )

    # Bust cache if requested
    Rails.cache.delete(cache_key) if bust_cache

    Rails.cache.fetch(cache_key, expires_in: CACHE_EXPIRY_MINUTES.minutes, race_condition_ttl: 5.seconds) do
      compute_availability_calendar(rental, start_date, end_date)
    end
  end
  
  # Get conflicting bookings for a rental during a time period
  #
  # @param rental [Product] the rental product
  # @param start_time [Time] start of period
  # @param end_time [Time] end of period
  # @param exclude_booking_id [Integer, nil] booking ID to exclude
  # @return [ActiveRecord::Relation] conflicting bookings
  def self.conflicting_bookings(rental:, start_time:, end_time:, exclude_booking_id: nil)
    return RentalBooking.none unless rental.rental?
    
    buffer = (rental.rental_buffer_mins || rental.business&.rental_buffer_mins || 0).minutes
    buffered_start = start_time - buffer
    buffered_end = end_time + buffer
    
    bookings = rental.rental_bookings
      .where.not(status: ['cancelled', 'completed'])
      .where('start_time < ? AND end_time > ?', buffered_end, buffered_start)
    
    bookings = bookings.where.not(id: exclude_booking_id) if exclude_booking_id
    bookings
  end
  
  # Find available time slots for a rental on a specific date
  # This is useful for hourly rentals
  #
  # @param rental [Product] the rental product
  # @param date [Date] the date to check
  # @param duration_mins [Integer] required duration in minutes
  # @param interval_mins [Integer] interval between slot starts (default: 60)
  # @return [Array<Hash>] available time slots with start_time and end_time
  def self.available_slots(rental:, date:, duration_mins:, interval_mins: nil, quantity: 1)
    return [] unless rental.rental?
    return [] if date < Date.current
    duration_mins = duration_mins.to_i
    return [] if duration_mins <= 0

    business = rental.business
    tz = business&.time_zone.presence || 'UTC'
    step_interval = slot_interval_minutes(rental: rental, duration_mins: duration_mins, override: interval_mins)

    Time.use_zone(tz) do
      windows = rental.rental_schedule_for(date)
      return [] if windows.blank?

      slots = []
      windows.each do |period|
        current_time = period[:start]
        end_boundary = period[:end] - duration_mins.minutes
        next if end_boundary <= current_time

        while current_time <= end_boundary
          slot_end = current_time + duration_mins.minutes
          if available?(rental: rental, start_time: current_time, end_time: slot_end, quantity: quantity)
            slots << { start_time: current_time, end_time: slot_end }
          end
          current_time += step_interval.minutes
        end
      end

      if date == Date.current
        now = Time.current
        slots.reject! { |slot| slot[:start_time] <= now }
      end

      slots
    end
  end
  
  # Clear cached availability for a rental
  #
  # @param rental [Product] the rental product
  def self.clear_cache(rental)
    return unless rental.rental?
    
    Rails.logger.info("[RentalAvailabilityService] Clearing cache for rental #{rental.id}")
    
    # Clear with pattern if supported
    if Rails.cache.respond_to?(:delete_matched) && 
       Rails.cache.class.name != "SolidCache::Store"
      cache_pattern = "rental_availability_#{rental.id}_*"
      Rails.cache.delete_matched(cache_pattern)
    end
    
    # Rotate cache-buster token
    Rails.cache.write("rental_avail_buster_#{rental.id}", SecureRandom.hex(6))
  end
  
  # ============================================
  # PRIVATE CLASS METHODS
  # ============================================
  
  private_class_method def self.compute_availability_calendar(rental, start_date, end_date)
    calendar = {}
    business = rental.business
    tz = business&.time_zone.presence || 'UTC'
    
    # Fetch all bookings in the date range (optimized query)
    range_start = start_date.in_time_zone(tz).beginning_of_day
    range_end = end_date.in_time_zone(tz).end_of_day
    
    bookings = rental.rental_bookings
      .where.not(status: ['cancelled', 'completed'])
      .where('start_time < ? AND end_time > ?', range_end, range_start)
      .pluck(:id, :start_time, :end_time, :quantity)
    
    (start_date..end_date).each do |date|
      day_start = date.in_time_zone(tz).beginning_of_day
      day_end = date.in_time_zone(tz).end_of_day
      
      # Calculate booked quantity for this day
      booked_qty = bookings.sum do |_id, b_start, b_end, qty|
        # Check if booking overlaps with this day
        (b_start < day_end && b_end > day_start) ? qty : 0
      end
      
      available = [rental.rental_quantity_available - booked_qty, 0].max
      
      calendar[date.to_s] = {
        date: date.to_s,
        available: available,
        total: rental.rental_quantity_available,
        fully_booked: available == 0,
        booked_count: booked_qty
      }
    end
    
    calendar
  end
  
  private_class_method def self.build_calendar_cache_key(rental:, start_date:, end_date:, tz:)
    base_key = "rental_availability_#{rental.id}_#{start_date}_#{end_date}_#{tz.parameterize(separator: '_')}"
    
    # Add version components
    version_components = []
    
    # Rental version
    version_components << "r_#{rental.updated_at.to_i}" if rental.updated_at.present?
    
    # Bookings change bucket (15-minute intervals)
    time_bucket = (Time.current.to_i / 900) * 900
    version_components << "b_#{time_bucket}"
    
    # Cache buster token
    buster = Rails.cache.fetch("rental_avail_buster_#{rental.id}") { SecureRandom.hex(6) }
    version_components << "v_#{buster}"
    
    "#{base_key}_#{version_components.join('_')}"
  end
  
  private_class_method def self.slot_interval_minutes(rental:, duration_mins:, override:)
    return override.to_i if override.present?

    policy = rental.business&.booking_policy
    if policy&.use_fixed_intervals?
      (policy.interval_mins || duration_mins).clamp(5, 480)
    elsif policy&.interval_mins.present?
      policy.interval_mins.clamp(5, 480)
    else
      duration_mins.clamp(5, 480)
    end
  end
end

