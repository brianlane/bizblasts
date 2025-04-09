# frozen_string_literal: true

class ServiceProvider < ApplicationRecord
  self.table_name = 'staff_members' # Explicitly set table name

  belongs_to :business # Specify FK is inferred correctly by Rails convention
  has_many :bookings, foreign_key: :staff_member_id, dependent: :restrict_with_error # Re-applying this change as it seems more consistent
  # has_many :bookings, dependent: :restrict_with_error # Remove booking association

  validates :business, presence: true # Update validation to use :business
  validates :name, presence: true, uniqueness: { scope: :business_id } # Scope remains business_id
  validates :active, inclusion: { in: [true, false] }
  # Add validations for email and phone format, allowing them to be blank
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  # Updated regex to be more permissive for common phone formats (incl. Faker)
  validates :phone, format: { with: /\A(?:\+?\d{1,3}[-.\s]?)?(?:\(?\d{1,3}\)?[-.\s]?)?\d{3}[-.\s]?\d{4}\z/, message: "must be a valid phone number" }, allow_blank: true

  # Validate the structure of the availability JSON upon saving
  validate :validate_availability_structure
  
  # Process the availability data before validation/save
  before_validation :process_availability

  # Checks if the service provider is available at a specific datetime.
  # Considers both weekly schedule and date-specific exceptions.
  #
  # @param datetime [DateTime, Time] The time to check availability for.
  # @return [Boolean] True if available, false otherwise.
  def available_at?(datetime)
    return false unless active? # Inactive providers are never available

    time_to_check = Tod::TimeOfDay(datetime)
    date_str = datetime.to_date.iso8601
    day_name = datetime.strftime('%A').downcase # monday, tuesday, etc.

    # Use Safe Navigation (&.) in case availability or exceptions are nil
    availability_data = self.availability&.with_indifferent_access || {}
    exceptions = availability_data[:exceptions] || {}
    weekly_schedule = availability_data.except(:exceptions)

    intervals = find_intervals_for(date_str, day_name, exceptions, weekly_schedule)

    # Check if the time falls within any of the valid intervals
    intervals.any? do |interval|
      start_time = parse_time_of_day(interval[:start])
      end_time = parse_time_of_day(interval[:end])

      start_time && end_time && time_to_check >= start_time && time_to_check < end_time
    end
  end

  private
  
  # Process availability data from form submission
  # This handles empty array submissions and ensures proper JSON structure
  def process_availability
    return if availability.blank?
    
    # Ensure availability is a hash/JSON
    self.availability = {} unless availability.is_a?(Hash)
    
    # Clean empty arrays or slots without both start and end times
    days_of_week = %w[monday tuesday wednesday thursday friday saturday sunday]
    
    # Handle regular weekdays
    days_of_week.each do |day|
      next unless availability[day].is_a?(Array)
      
      # Filter out invalid time slots
      valid_slots = availability[day].select do |slot|
        slot.is_a?(Hash) && 
        slot['start'].present? && 
        slot['end'].present?
      end
      
      availability[day] = valid_slots
    end
    
    # Handle exceptions
    if availability['exceptions'].is_a?(Hash)
      availability['exceptions'].each do |date, slots|
        if slots.is_a?(Array)
          # Filter out invalid slots
          valid_slots = slots.select do |slot|
            slot.is_a?(Hash) && 
            slot['start'].present? && 
            slot['end'].present?
          end
          
          availability['exceptions'][date] = valid_slots
        else # Handle non-array or blank values by converting to empty array
          availability['exceptions'][date] = []
        end
      end
    elsif availability.key?('exceptions') # Handle case where 'exceptions' key exists but value isn't a hash
      availability['exceptions'] = {}
    end
  end

  # Finds the applicable time intervals for a given date/day.
  # Checks exceptions first, then falls back to the weekly schedule.
  def find_intervals_for(date_str, day_name, exceptions, weekly_schedule)
    # Check for date-specific exceptions first
    if exceptions.key?(date_str)
      exceptions[date_str] || [] # Return exception intervals or empty array if explicitly closed
    else
      # Fallback to weekly schedule
      weekly_schedule[day_name] || [] # Return day's intervals or empty array if day not defined
    end
  end

  # Safely parses a time string ("HH:MM") into a Tod::TimeOfDay object.
  def parse_time_of_day(time_str)
    Tod::TimeOfDay.parse(time_str)
  rescue ArgumentError # Handle invalid time formats
    Rails.logger.warn("Invalid time format in availability JSON: #{time_str}")
    nil
  end

  # Validates the structure of the 'availability' JSON field.
  def validate_availability_structure
    return if availability.blank? # Allow blank availability

    unless availability.is_a?(Hash)
      errors.add(:availability, :invalid_format, message: "must be a valid JSON object")
      return
    end

    days_of_week = %w[monday tuesday wednesday thursday friday saturday sunday]
    valid_keys = days_of_week + ['exceptions']

    availability.each do |key, value|
      key_str = key.to_s.downcase
      unless valid_keys.include?(key_str)
        errors.add(:availability, :invalid_key, message: "contains invalid key: '#{key}'. Allowed keys are days of the week and 'exceptions'.")
        next
      end

      if key_str == 'exceptions'
        validate_exceptions_structure(value)
      else # It's a day of the week
        validate_day_intervals_structure(key_str, value)
      end
    end
  end

  # Validates the structure of the 'exceptions' part of the availability JSON.
  def validate_exceptions_structure(exceptions_hash)
    unless exceptions_hash.is_a?(Hash)
      errors.add(:availability, :invalid_exceptions_format, message: "'exceptions' value must be a JSON object")
      return
    end

    exceptions_hash.each do |date_str, intervals|
      begin
        Date.iso8601(date_str) # Check if the date string is valid ISO 8601 format
      rescue Date::Error
        errors.add(:availability, :invalid_exception_date, message: "contains invalid date format in exceptions: '#{date_str}'. Use YYYY-MM-DD.")
        next
      end
      validate_day_intervals_structure("exception date #{date_str}", intervals)
    end
  end

  # Validates the structure of time intervals for a given day or exception date.
  def validate_day_intervals_structure(day_key, intervals)
    unless intervals.is_a?(Array)
      errors.add(:availability, :invalid_intervals_format, message: "value for '#{day_key}' must be an array of time intervals")
      return
    end

    intervals.each_with_index do |interval, index|
      unless interval.is_a?(Hash) && interval.key?('start') && interval.key?('end')
        errors.add(:availability, :invalid_interval_format, message: "interval ##{index + 1} for '#{day_key}' must be an object with 'start' and 'end' keys")
        next # Skip time validation if format is wrong
      end

      validate_time_string(day_key, interval['start'], "start time for interval ##{index + 1}")
      validate_time_string(day_key, interval['end'], "end time for interval ##{index + 1}")

      # Optional: Validate that end time is after start time within the interval
      start_tod = Tod::TimeOfDay.parse(interval['start']) rescue nil
      end_tod = Tod::TimeOfDay.parse(interval['end']) rescue nil
      if start_tod && end_tod && start_tod >= end_tod
         errors.add(:availability, :invalid_interval_order, message: "start time must be before end time for interval ##{index + 1} on '#{day_key}'")
      end
    end
  end

  # Validates a single time string ("HH:MM").
  def validate_time_string(day_key, time_str, description)
    return if time_str.blank? # Allow blank times? Decide based on requirements.

    # First check format with regex to ensure it matches HH:MM format
    unless time_str.match?(/\A\d{2}:\d{2}\z/)
      errors.add(:availability, :invalid_time_format, message: "invalid #{description} for '#{day_key}': '#{time_str}'. Use HH:MM format.")
      return
    end

    # Then try to parse it to ensure it's a valid time
    begin
      Tod::TimeOfDay.parse(time_str)
    rescue ArgumentError
      errors.add(:availability, :invalid_time_format, message: "invalid #{description} for '#{day_key}': '#{time_str}'. Use HH:MM format.")
    end
  end
end 