# frozen_string_literal: true

class StaffMember < ApplicationRecord
  include TenantScoped
  
  acts_as_tenant(:business)
  belongs_to :business
  belongs_to :user, optional: true
  has_many :bookings, dependent: :restrict_with_error
  has_many :services_staff_members, dependent: :destroy
  has_many :services, through: :services_staff_members
  
  validates :name, presence: true, uniqueness: { scope: :business_id }
  validates :active, inclusion: { in: [true, false] }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :phone, presence: true, format: { with: /\A(?:\+?\d{1,3}[-.\s]?)?(?:\(?\d{1,3}\)?[-.\s]?)?\d{3}[-.\s]?\d{4}\z/, message: "must be a valid phone number" }, allow_blank: true
  
  validate :validate_availability_structure
  before_validation :process_availability
  
  scope :active, -> { where(active: true) }
  
  # Returns the staff member's name for display purposes
  # This is an alias for the name attribute to maintain compatibility with views
  def full_name
    name
  end
  
  def available_services
    services.where(active: true)
  end
  
  def upcoming_bookings
    bookings.upcoming
  end
  
  def today_bookings
    bookings.today
  end
  
  def calendar_data
    bookings.upcoming.map do |booking|
      {
        id: booking.id,
        title: booking.tenant_customer.name,
        start: booking.start_time,
        end: booking.end_time,
        status: booking.status
      }
    end
  end
  
  def available_at?(datetime)
    return false unless active?

    time_to_check = Tod::TimeOfDay(datetime)
    date_str = datetime.to_date.iso8601
    day_name = datetime.strftime('%A').downcase

    availability_data = self.availability&.with_indifferent_access || {}
    exceptions = availability_data[:exceptions] || {}
    weekly_schedule = availability_data.except(:exceptions)
    
    # Debug
    Rails.logger.debug("Checking availability at: #{datetime.strftime('%Y-%m-%d %H:%M:%S')}")
    Rails.logger.debug("Time of day: #{time_to_check}, Date: #{date_str}, Day: #{day_name}")

    # Add explicit debug when checking exceptions
    if exceptions.key?(date_str)
      Rails.logger.debug("Found exception for date: #{date_str}")
      Rails.logger.debug("Exception intervals: #{exceptions[date_str].inspect}")
    end

    intervals = find_intervals_for(date_str, day_name, exceptions, weekly_schedule)

    if intervals.empty?
      Rails.logger.debug("No intervals found, returning not available")
      return false
    end
    
    Rails.logger.debug("Found #{intervals.count} intervals for #{day_name}/#{date_str}: #{intervals.inspect}")

    available = intervals.any? do |interval|
      start_time = parse_time_of_day(interval[:start] || interval['start'])
      end_time = parse_time_of_day(interval[:end] || interval['end'])
      
      result = start_time && end_time && time_to_check >= start_time && time_to_check < end_time
      Rails.logger.debug("  - Interval #{interval[:start] || interval['start']} to #{interval[:end] || interval['end']}: #{result ? 'AVAILABLE' : 'NOT AVAILABLE'}")
      result
    end
    
    Rails.logger.debug("Final availability result: #{available}")
    available
  end
  
  def self.ransackable_attributes(auth_object = nil)
    %w[id name email phone bio active business_id user_id position created_at updated_at photo_url]
  end
  
  def self.ransackable_associations(auth_object = nil)
    %w[business bookings services user services_staff_members]
  end
  
  private
  
  def process_availability
    return if availability.blank?
    self.availability = {} unless availability.is_a?(Hash)
    days_of_week = %w[monday tuesday wednesday thursday friday saturday sunday]
    days_of_week.each do |day|
      next unless availability[day].is_a?(Array)
      valid_slots = availability[day].select { |s| s.is_a?(Hash) && s['start'].present? && s['end'].present? }
      availability[day] = valid_slots
    end
    if availability['exceptions'].is_a?(Hash)
      availability['exceptions'].each do |date, slots|
        if slots.is_a?(Array)
          valid_slots = slots.select { |s| s.is_a?(Hash) && s['start'].present? && s['end'].present? }
          availability['exceptions'][date] = valid_slots
        else
          availability['exceptions'][date] = []
        end
      end
    elsif availability.key?('exceptions')
      availability['exceptions'] = {}
    end
  end

  def find_intervals_for(date_str, day_name, exceptions, weekly_schedule)
    if exceptions.key?(date_str)
      exceptions[date_str] || []
    else
      weekly_schedule[day_name] || []
    end
  end

  def parse_time_of_day(time_str)
    Tod::TimeOfDay.parse(time_str)
  rescue ArgumentError
    Rails.logger.warn("Invalid time format in availability JSON: #{time_str}")
    nil
  end

  def validate_availability_structure
    return if availability.blank?
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
      else
        validate_day_intervals_structure(key_str, value)
      end
    end
  end

  def validate_exceptions_structure(exceptions_hash)
    unless exceptions_hash.is_a?(Hash)
      errors.add(:availability, :invalid_exceptions_format, message: "'exceptions' value must be a JSON object")
      return
    end
    exceptions_hash.each do |date_str, intervals|
      begin
        Date.iso8601(date_str)
      rescue Date::Error
        errors.add(:availability, :invalid_exception_date, message: "contains invalid date format in exceptions: '#{date_str}'. Use YYYY-MM-DD.")
        next
      end
      validate_day_intervals_structure("exception date #{date_str}", intervals)
    end
  end

  def validate_day_intervals_structure(day_key, intervals)
    unless intervals.is_a?(Array)
      errors.add(:availability, :invalid_intervals_format, message: "value for '#{day_key}' must be an array of time intervals")
      return
    end
    intervals.each_with_index do |interval, index|
      unless interval.is_a?(Hash) && interval.key?('start') && interval.key?('end')
        errors.add(:availability, :invalid_interval_format, message: "interval ##{index + 1} for '#{day_key}' must be an object with 'start' and 'end' keys")
        next
      end
      validate_time_string(day_key, interval['start'], "start time for interval ##{index + 1}")
      validate_time_string(day_key, interval['end'], "end time for interval ##{index + 1}")
      start_tod = Tod::TimeOfDay.parse(interval['start']) rescue nil
      end_tod = Tod::TimeOfDay.parse(interval['end']) rescue nil
      if start_tod && end_tod && start_tod >= end_tod
         errors.add(:availability, :invalid_interval_order, message: "start time must be before end time for interval ##{index + 1} on '#{day_key}'")
      end
    end
  end

  def validate_time_string(day_key, time_str, description)
    return if time_str.blank?
    unless time_str.match?(/\A\d{2}:\d{2}\z/)
      errors.add(:availability, :invalid_time_format, message: "invalid #{description} for '#{day_key}': '#{time_str}'. Use HH:MM format.")
      return
    end
    begin
      Tod::TimeOfDay.parse(time_str)
    rescue ArgumentError
      errors.add(:availability, :invalid_time_format, message: "invalid #{description} for '#{day_key}': '#{time_str}'. Use HH:MM format.")
    end
  end
end
