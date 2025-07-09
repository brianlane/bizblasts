# frozen_string_literal: true

class StaffMember < ApplicationRecord
  belongs_to :business
  validates :business, presence: true
  belongs_to :user, optional: true
  
  # Active Storage attachment for photo
  has_one_attached :photo do |attachable|
    attachable.variant :thumb, resize_to_limit: [150, 150], quality: 80
    attachable.variant :medium, resize_to_limit: [300, 300], quality: 85
  end
  # Virtual attribute for selecting user role (staff or manager)
  attr_accessor :user_role
  accepts_nested_attributes_for :user, reject_if: :all_blank
  has_many :bookings, dependent: :restrict_with_error
  has_many :services_staff_members, dependent: :destroy
  has_many :services, through: :services_staff_members
  
  # Bidirectional deletion: when staff member is deleted, delete associated user
  before_destroy :delete_associated_user, if: -> { user.present? }
  
  validates :name, presence: true, uniqueness: { scope: :business_id }
  validates :active, inclusion: { in: [true, false] }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :phone, presence: true, format: { with: /\A(?:\+?\d{1,3}[-.\s]?)?(?:\(?\d{1,3}\)?[-.\s]?)?\d{3}[-.\s]?\d{4}\z/, message: "must be a valid phone number" }, allow_blank: true
  
  # Photo validations
  validates :photo, content_type: { in: %w[image/png image/jpeg image/gif image/webp], 
                                   message: 'must be PNG, JPEG, GIF, or WebP' },
                   size: { less_than: 15.megabytes, message: 'must be less than 15MB' }
  
  validate :validate_availability_structure
  before_validation :process_availability
  before_validation :set_default_name_from_user

  
  # Background processing for photo
  after_commit :process_photo, if: -> { photo.attached? }
  
  scope :active, -> { where(active: true) }
  
  # Returns the staff member's name for display purposes
  # This is an alias for the name attribute to maintain compatibility with views
  def full_name
    name
  end
  
  # Check if the associated user is a manager
  def manager?
    user&.manager?
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
        title: booking.tenant_customer.full_name,
        start: booking.start_time,
        end: booking.end_time,
        status: booking.status
      }
    end
  end
  
  def available_at?(datetime)
    return false unless active?

    time_to_check = Tod::TimeOfDay(datetime)
    availability_data = self.availability&.with_indifferent_access || {}
    exceptions = availability_data[:exceptions] || {}
    weekly_schedule = availability_data.except(:exceptions)

    # Check current day's schedule for availability
    current_date = datetime.to_date
    current_day_name = current_date.strftime('%A').downcase
    current_day_intervals = find_intervals_for(current_date.iso8601, current_day_name, exceptions, weekly_schedule)

    current_day_intervals.each do |interval|
      start_tod = parse_time_of_day(interval['start'])
      end_tod = parse_time_of_day(interval['end'])
      next unless start_tod && end_tod

      is_overnight = start_tod > end_tod || (end_tod == Tod::TimeOfDay.new(0) && start_tod != Tod::TimeOfDay.new(0))
      
      if is_overnight
        # For an overnight shift, check if the time is on or after the start time on this day
        return true if time_to_check >= start_tod
      else
        # For a same-day shift, check if the time is within the interval
        return true if time_to_check >= start_tod && time_to_check < end_tod
      end
    end

    # Check previous day's schedule for overnight spillover
    previous_date = datetime.to_date - 1.day
    previous_day_name = previous_date.strftime('%A').downcase
    previous_day_intervals = find_intervals_for(previous_date.iso8601, previous_day_name, exceptions, weekly_schedule)

    previous_day_intervals.each do |interval|
      start_tod = parse_time_of_day(interval['start'])
      end_tod = parse_time_of_day(interval['end'])
      next unless start_tod && end_tod
      
      is_overnight = start_tod > end_tod || (end_tod == Tod::TimeOfDay.new(0) && start_tod != Tod::TimeOfDay.new(0))

      if is_overnight
        # If the previous day had an overnight shift, check if the current time falls in the spillover period
        return true if time_to_check < end_tod
      end
    end

    # If no availability is found in either check, return false
    false
  end
  
  def self.ransackable_attributes(auth_object = nil)
    %w[id name email phone bio active business_id user_id position created_at updated_at photo_url status specialties timezone color]
  end
  
  def self.ransackable_associations(auth_object = nil)
    %w[business bookings services user services_staff_members]
  end
  
  def hours_booked_this_month
    start_of_month = Time.current.beginning_of_month
    end_of_month = Time.current.end_of_month
    bookings_in_month = bookings.where(start_time: start_of_month..end_of_month)
                              .where(status: [:confirmed, :completed])
    bookings_in_month.sum do |booking|
      if booking.start_time && booking.end_time
        ((booking.end_time - booking.start_time) / 1.hour).to_f
      else
        0.0
      end
    end
  end

  def hours_completed_this_month
    start_of_month = Time.current.beginning_of_month
    end_of_month = Time.current.end_of_month
    completed_bookings = bookings.where(start_time: start_of_month..end_of_month, status: :completed)
    completed_bookings.sum do |booking|
      if booking.start_time && booking.end_time
        ((booking.end_time - booking.start_time) / 1.hour).to_f
      else
        0.0
      end
    end
  end
  
  private

  def set_default_name_from_user
    if name.blank? && user.present? && user.first_name.present?
      self.name = "#{user.first_name} #{user.last_name}".strip
    end
  end
  
  def process_photo
    return unless photo.attached?
    
    begin
      return unless photo.blob.byte_size > 2.megabytes
      # Pass the attachment ID instead of the attached object
      ProcessImageJob.perform_later(photo.attachment.id)
    rescue ActiveStorage::FileNotFoundError => e
      Rails.logger.warn "Photo blob not found for staff member #{id}: #{e.message}"
    rescue => e
      Rails.logger.error "Failed to enqueue photo processing job for staff member #{id}: #{e.message}"
    end
  end
  
  def delete_associated_user
    return unless user.present?
    
    # Temporarily store the user and remove the association to prevent infinite loops
    user_to_delete = self.user
    self.update_column(:user_id, nil)  # Use update_column to persist the change without callbacks
    user_to_delete.destroy
  end

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
      Rails.logger.debug("find_intervals_for: Using exception for #{date_str}")
      exceptions[date_str] || []
    else
      Rails.logger.debug("find_intervals_for: Using weekly schedule for #{day_name}")
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
      if start_tod && end_tod
        # An interval is invalid if the start time is on or after the end time,
        # unless the end time is midnight (00:00), which signifies an overnight availability.
        is_overnight_slot = (end_tod == Tod::TimeOfDay.new(0)) && (start_tod != Tod::TimeOfDay.new(0))
        if !is_overnight_slot && start_tod >= end_tod
          errors.add(:availability, :invalid_interval_order, message: "start time must be before end time for interval ##{index + 1} on '#{day_key}'")
        end
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
