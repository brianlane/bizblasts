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
  has_many :calendar_connections, dependent: :destroy
  has_many :video_meeting_connections, dependent: :destroy
  belongs_to :default_calendar_connection, class_name: 'CalendarConnection', optional: true

  # --------------------------------------------------------------------------
  # Calendar connection integrity
  # --------------------------------------------------------------------------
  # Ensure the chosen default connection actually belongs to this staff member
  validate  :default_calendar_connection_must_belong_to_staff_member
  # Break the circular foreign-key dependency between staff_members.default_calendar_connection_id
  # and calendar_connections.staff_member_id by clearing the reference before destroy.
  before_destroy :clear_default_calendar_connection_id
  
  # Bidirectional deletion: when staff member is deleted, delete associated user
  before_destroy :delete_associated_user, if: -> { user.present? }
  
  validates :name, presence: true, uniqueness: { scope: :business_id }
  validates :active, inclusion: { in: [true, false] }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :phone, presence: true, format: { with: /\A(?:\+?\d{1,3}[-.\s]?)?(?:\(?\d{1,3}\)?[-.\s]?)?\d{3}[-.\s]?\d{4}\z/, message: "must be a valid phone number" }, allow_blank: true
  
  # Photo validations - Updated for HEIC support
  validates :photo, **FileUploadSecurity.image_validation_options
  
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

    time_to_check = Tod::TimeOfDay.parse(datetime.strftime('%H:%M'))
    availability_data = self.availability&.with_indifferent_access || {}
    exceptions = availability_data[:exceptions] || {}
    weekly_schedule = availability_data.except(:exceptions)

    # Check today's intervals
    current_date = datetime.to_date
    current_day_name = current_date.strftime('%A').downcase
    current_day_intervals = find_intervals_for(current_date.iso8601, current_day_name, exceptions, weekly_schedule)

    current_day_intervals.each do |interval|
      interval = interval.with_indifferent_access
      start_tod = parse_time_of_day(interval['start'])
      end_tod   = parse_time_of_day(interval['end'])
      next unless start_tod && end_tod

      # Full-day availability (00:00 to 23:59)
      if start_tod == Tod::TimeOfDay.new(0, 0) && end_tod == Tod::TimeOfDay.new(23, 59)
        return true
      end

      # Normal same-day interval (no overnight shifts supported)
      if start_tod < end_tod
        return true if time_to_check >= start_tod && time_to_check < end_tod
      end
    end

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
  
  # Calendar integration methods
  def has_calendar_integrations?
    calendar_connections.active.any?
  end
  
  def google_calendar_connected?
    calendar_connections.google_connections.active.any?
  end
  
  def microsoft_calendar_connected?
    calendar_connections.microsoft_connections.active.any?
  end
  
  def caldav_calendar_connected?
    calendar_connections.caldav_connections.active.any?
  end
  
  def active_calendar_connections
    calendar_connections.active
  end
  
  def calendar_sync_status
    connections = active_calendar_connections
    return 'No integrations' if connections.empty?
    
    # All connections have never completed a sync yet (just connected)
    if connections.all? { |c| c.last_synced_at.nil? }
      'Syncing'
    # Every connection synced in the last hour
    elsif connections.all? { |c| c.last_synced_at && c.last_synced_at > 1.hour.ago }
      'All synced'
    # One or more connections have not synced in 6+ hours
    elsif connections.any? { |c| c.last_synced_at.nil? || c.last_synced_at < 6.hours.ago }
      'Sync issues'
    else
      'Needs sync'
    end
  end
  
  def primary_calendar_connection
    default_calendar_connection || active_calendar_connections.first
  end
  
  # Booking sync statistics
  def synced_bookings_count(since: 30.days.ago)
    bookings.where(calendar_event_status: :synced)
            .where(created_at: since..)
            .count
  end
  
  def pending_sync_bookings_count
    bookings.where(calendar_event_status: [:not_synced, :sync_pending]).count
  end
  
  def failed_sync_bookings_count
    bookings.where(calendar_event_status: :sync_failed).count
  end
  
  def total_bookings_requiring_sync_count(since: 30.days.ago)
    return 0 unless has_calendar_integrations?
    
    bookings.where(created_at: since..)
            .where.not(calendar_event_status: :not_synced)
            .count
  end
  
  def calendar_sync_success_rate(since: 30.days.ago)
    total = total_bookings_requiring_sync_count(since: since)
    return 0 if total.zero?

    synced = synced_bookings_count(since: since)
    (synced.to_f / total * 100).round(1)
  end

  # Video meeting integration methods
  def has_video_meeting_integrations?
    video_meeting_connections.active.any?
  end

  def zoom_connected?
    video_meeting_connections.zoom_connections.active.exists?
  end

  def google_meet_connected?
    video_meeting_connections.google_meet_connections.active.exists?
  end

  def has_video_connection?(provider)
    return false if provider.nil?
    video_meeting_connections.active.exists?(provider: provider)
  end

  def video_connection_for(provider)
    return nil if provider.nil?
    video_meeting_connections.active.find_by(provider: provider)
  end

  def active_video_meeting_connections
    video_meeting_connections.active
  end

  def video_meeting_status_summary
    connections = active_video_meeting_connections
    return 'No video integrations' if connections.empty?

    providers = connections.map(&:provider_name).join(', ')
    "Connected: #{providers}"
  end

  private

  # --------------------------------------------------------------------------
  # Validation helpers
  # --------------------------------------------------------------------------
  def default_calendar_connection_must_belong_to_staff_member
    return if default_calendar_connection.blank?

    if default_calendar_connection.staff_member_id != id
      errors.add(:default_calendar_connection_id, :invalid, message: 'must reference a calendar connection belonging to the same staff member')
    end
  end

  # --------------------------------------------------------------------------
  # Callback helpers
  # --------------------------------------------------------------------------
  def clear_default_calendar_connection_id
    # Use update_column to avoid validation callbacks which could fail if the
    # default connection is already being destroyed in the same transaction.
    update_column(:default_calendar_connection_id, nil) if default_calendar_connection_id.present?
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
      end_tod   = Tod::TimeOfDay.parse(interval['end'])   rescue nil
      if start_tod && end_tod
        # Valid interval conditions:
        # 1) Normal: start before end on same day
        # 2) Full day: exactly 00:00 to 23:59 (24-hour availability)
        is_normal    = start_tod < end_tod
        is_full_day  = (start_tod == Tod::TimeOfDay.new(0, 0)) && (end_tod == Tod::TimeOfDay.new(23, 59))
        
        unless is_normal || is_full_day
          if start_tod >= end_tod
            errors.add(
              :availability,
              :invalid_interval_order,
              message: "Shifts are not supported for interval ##{index + 1} on '#{day_key}'. Use 'Full 24 Hour Availability' or set separate intervals for each day"
            )
          end
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
