# Service object to handle service availability management
# Extracts complex logic from ServicesController#manage_availability
class ServiceAvailabilityManager
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations

  attr_reader :service, :date_range, :calendar_data, :errors

  def initialize(service:, date: nil, logger: Rails.logger)
    @service = service
    @date = parse_date(date)
    @start_date = @date.beginning_of_week
    @end_date = @date.end_of_week
    @date_range = (@start_date..@end_date)
    @logger = logger
    @errors = []
    @calendar_data = {}

    ensure_availability_structure
  end

  # Update service availability from form parameters
  def update_availability(availability_params, full_day_params = {})
    begin
      availability_data = build_availability_data(availability_params, full_day_params)
      
      if validate_availability_data(availability_data)
        update_result = @service.update(availability: availability_data)
        
        if update_result
          @logger.info("Service availability updated successfully for service #{@service.id}")
          true
        else
          @errors.concat(@service.errors.full_messages)
          @logger.error("Failed to update service availability for service #{@service.id}: #{@service.errors.full_messages}")
          false
        end
      else
        @logger.warn("Invalid availability data for service #{@service.id}: #{@errors}")
        false
      end
    rescue => e
      @logger.error("Exception in ServiceAvailabilityManager#update_availability: #{e.message}")
      @logger.error(e.backtrace.join("\n"))
      @errors << "An unexpected error occurred while updating availability"
      false
    end
  end

  # Update enforcement setting
  def update_enforcement(enforce_value)
    begin
      enforcement_boolean = ActiveModel::Type::Boolean.new.cast(enforce_value)
      result = @service.update(enforce_service_availability: enforcement_boolean)
      
      if result
        @logger.info("Service availability enforcement updated to #{enforcement_boolean} for service #{@service.id}")
      else
        @logger.error("Failed to update enforcement setting for service #{@service.id}: #{@service.errors.full_messages}")
        @errors.concat(@service.errors.full_messages)
      end
      
      result
    rescue => e
      @logger.error("Exception updating enforcement setting: #{e.message}")
      @errors << "Failed to update enforcement setting"
      false
    end
  end

  # Generate calendar data for preview
  def generate_calendar_data(bust_cache: false)
    begin
      @calendar_data = {}
      
      @date_range.each do |date|
        date_slots = []
        
        @service.staff_members.active.find_each do |staff|
          staff_slots = AvailabilityService.available_slots(
            staff, 
            date, 
            @service, 
            interval: 60,  # Default to hourly slots
            bust_cache: bust_cache
          )
          date_slots.concat(staff_slots)
        end
        
        @calendar_data[date.to_s] = date_slots.sort_by { |slot| slot[:start_time] }
      end
      
      @calendar_data
    rescue => e
      @logger.error("Exception generating calendar data: #{e.message}")
      @logger.error(e.backtrace.join("\n"))
      @errors << "Failed to generate calendar preview"
      {}
    end
  end

  # Get formatted date information
  def date_info
    {
      current_date: @date,
      start_date: @start_date,
      end_date: @end_date,
      week_range: "#{@start_date.strftime('%b %d')} - #{@end_date.strftime('%b %d, %Y')}"
    }
  end

  # Check if service has valid availability structure
  def valid_availability_structure?
    return false unless @service.availability.is_a?(Hash)
    
    required_days = %w[monday tuesday wednesday thursday friday saturday sunday]
    required_days.all? { |day| @service.availability.key?(day) } &&
      @service.availability.key?('exceptions')
  end

  private

  # Parse and validate date parameter
  def parse_date(date_param)
    return Date.current unless date_param.present?
    
    begin
      parsed_date = Date.parse(date_param.to_s)
      
      # Validate date is reasonable (within 2 years of today)
      if parsed_date < 2.years.ago || parsed_date > 2.years.from_now
        @logger.warn("Date parameter out of reasonable range: #{parsed_date}, using current date")
        Date.current
      else
        parsed_date
      end
    rescue ArgumentError, TypeError => e
      @logger.warn("Invalid date parameter: #{date_param}, error: #{e.message}")
      Date.current
    end
  end

  # Ensure service has proper availability structure
  def ensure_availability_structure
    unless valid_availability_structure?
      default_availability = {
        'monday' => [],
        'tuesday' => [],
        'wednesday' => [],
        'thursday' => [],
        'friday' => [],
        'saturday' => [],
        'sunday' => [],
        'exceptions' => {}
      }
      
      @service.update_column(:availability, default_availability)
      @logger.info("Initialized default availability structure for service #{@service.id}")
    end
  end

  # Build availability data from form parameters
  def build_availability_data(availability_params, full_day_params)
    availability_data = initialize_availability_structure

    days = @date_range.map { |date| date.strftime('%A').downcase }

    days.each do |day|
      if full_day_params[day] == '1'
        availability_data[day] = [{ 'start' => '00:00', 'end' => '23:59' }]
      else
        day_params = availability_params[day] || {}
        slots = extract_time_slots(day_params)
        availability_data[day] = slots
      end
    end

    availability_data
  end

  # Initialize empty availability structure
  def initialize_availability_structure
    {
      'monday' => [],
      'tuesday' => [],
      'wednesday' => [],
      'thursday' => [],
      'friday' => [],
      'saturday' => [],
      'sunday' => [],
      'exceptions' => {}
    }
  end

  # Extract and validate time slots from day parameters
  def extract_time_slots(day_params)
    return [] unless day_params.is_a?(Hash)

    day_params.values.filter_map do |slot_data|
      next unless slot_data.is_a?(Hash)
      next unless slot_data['start'].present? && slot_data['end'].present?

      start_time = slot_data['start'].to_s.strip
      end_time = slot_data['end'].to_s.strip

      if valid_time_format?(start_time) && valid_time_format?(end_time)
        { 'start' => start_time, 'end' => end_time }
      else
        @logger.warn("Invalid time format in slot: start=#{start_time}, end=#{end_time}")
        nil
      end
    end.compact
  end

  # Validate time format (HH:MM)
  def valid_time_format?(time_str)
    time_str.match?(/\A([01]?[0-9]|2[0-3]):[0-5][0-9]\z/)
  end

  # Validate availability data structure and logic
  def validate_availability_data(availability_data)
    return false unless availability_data.is_a?(Hash)

    valid = true

    availability_data.each do |day, slots|
      next if day == 'exceptions'
      next unless slots.is_a?(Array)

      slots.each do |slot|
        unless valid_time_slot?(slot)
          @errors << "Invalid time slot format for #{day.capitalize}"
          valid = false
        end
      end

      if slots.length > 1 && overlapping_slots?(slots)
        @errors << "Overlapping time slots detected for #{day.capitalize}"
        valid = false
      end
    end

    valid
  end

  # Validate individual time slot
  def valid_time_slot?(slot)
    return false unless slot.is_a?(Hash)
    return false unless slot['start'].present? && slot['end'].present?

    start_time = slot['start']
    end_time = slot['end']

    # Validate time format
    return false unless valid_time_format?(start_time) && valid_time_format?(end_time)

    # Validate logical order
    start_minutes = time_to_minutes(start_time)
    end_minutes = time_to_minutes(end_time)

    if start_minutes >= end_minutes
      @errors << "End time must be after start time (#{start_time} - #{end_time})"
      return false
    end

    # Validate minimum duration (15 minutes)
    if (end_minutes - start_minutes) < 15
      @errors << "Time slots must be at least 15 minutes long (#{start_time} - #{end_time})"
      return false
    end

    true
  end

  # Check for overlapping slots within a day
  def overlapping_slots?(slots)
    return false if slots.length < 2

    sorted_slots = slots.sort_by { |slot| time_to_minutes(slot['start']) }

    sorted_slots.each_cons(2) do |slot1, slot2|
      if time_to_minutes(slot1['end']) > time_to_minutes(slot2['start'])
        return true
      end
    end

    false
  end

  # Convert time string to minutes since midnight
  def time_to_minutes(time_str)
    hours, minutes = time_str.split(':').map(&:to_i)
    (hours * 60) + minutes
  end
end