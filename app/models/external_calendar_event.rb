# frozen_string_literal: true

class ExternalCalendarEvent < ApplicationRecord
  belongs_to :calendar_connection
  
  validates :calendar_connection_id, presence: true
  validates :external_event_id, presence: true
  validates :starts_at, presence: true
  validates :ends_at, presence: true
  validate :end_time_after_start_time
  
  # Ensure unique external event ID per calendar connection
  validates :external_event_id, uniqueness: { scope: :calendar_connection_id }
  
  scope :in_date_range, ->(start_date, end_date) {
    where(starts_at: start_date.beginning_of_day..end_date.end_of_day)
  }
  scope :overlapping, ->(start_time, end_time) {
    where('starts_at < ? AND ends_at > ?', end_time, start_time)
  }
  scope :recent, -> { order(last_imported_at: :desc) }
  scope :stale, -> { where('last_imported_at < ?', 1.hour.ago) }
  scope :today, -> { in_date_range(Date.current, Date.current) }
  scope :upcoming, -> { where('starts_at > ?', Time.current) }
  scope :past, -> { where('ends_at < ?', Time.current) }
  
  delegate :staff_member, to: :calendar_connection
  delegate :business, to: :calendar_connection
  delegate :provider, to: :calendar_connection
  delegate :provider_display_name, to: :calendar_connection
  
  # Callbacks
  before_validation :normalize_times
  after_create :log_import

  # Invalidate cached availability whenever external events change
  after_create_commit :clear_staff_availability_cache
  after_update_commit :clear_staff_availability_cache
  after_destroy_commit :clear_staff_availability_cache
  
  def self.import_for_connection(connection, events_data)
    imported_count = 0
    errors = []
    
    events_data.each do |event_data|
      begin
        external_event = find_or_initialize_by(
          calendar_connection: connection,
          external_event_id: event_data[:external_event_id]
        )
        
        external_event.assign_attributes(
          external_calendar_id: event_data[:external_calendar_id],
          starts_at: event_data[:starts_at],
          ends_at: event_data[:ends_at],
          summary: event_data[:summary],
          last_imported_at: Time.current
        )
        
        if external_event.save
          imported_count += 1
        else
          errors << "Event #{event_data[:external_event_id]}: #{external_event.errors.full_messages.join(', ')}"
        end
      rescue => e
        errors << "Event #{event_data[:external_event_id]}: #{e.message}"
      end
    end
    
    { imported_count: imported_count, errors: errors }
  end
  
  def self.cleanup_old_events(older_than: 30.days.ago)
    where('ends_at < ?', older_than).delete_all
  end
  
  def self.conflicts_with_booking(booking)
    return none unless booking.start_time && booking.end_time && booking.staff_member
    
    staff_connections = booking.staff_member.calendar_connections.active
    return none if staff_connections.empty?
    
    joins(:calendar_connection)
      .where(calendar_connections: { id: staff_connections.ids })
      .overlapping(booking.start_time, booking.end_time)
  end
  
  def duration
    return 0 if starts_at.blank? || ends_at.blank?
    ((ends_at - starts_at) / 1.hour).round(2)
  end
  
  def duration_in_minutes
    return 0 if starts_at.blank? || ends_at.blank?
    ((ends_at - starts_at) / 1.minute).round
  end
  
  def overlaps_with?(start_time, end_time)
    starts_at < end_time && ends_at > start_time
  end
  
  def formatted_time_range
    return '' if starts_at.blank? || ends_at.blank?
    
    if starts_at.to_date == ends_at.to_date
      "#{starts_at.strftime('%b %d, %Y %I:%M %p')} - #{ends_at.strftime('%I:%M %p')}"
    else
      "#{starts_at.strftime('%b %d, %Y %I:%M %p')} - #{ends_at.strftime('%b %d, %Y %I:%M %p')}"
    end
  end
  
  def display_summary
    return 'Untitled Event' if summary.blank?
    summary.length > 50 ? "#{summary[0..47]}..." : summary
  end
  
  def all_day_event?
    return false if starts_at.blank? || ends_at.blank?
    
    # Check if event spans exactly 24 hours and starts at midnight
    starts_at.hour == 0 && starts_at.min == 0 && 
    (ends_at - starts_at) >= 23.hours && 
    (ends_at.hour == 0 && ends_at.min == 0)
  end
  
  def import_age
    return 'Never imported' if last_imported_at.blank?
    
    time_ago = Time.current - last_imported_at
    case time_ago
    when 0..1.hour
      'Recently imported'
    when 1.hour..1.day
      "#{(time_ago / 1.hour).round} hours ago"
    else
      "#{(time_ago / 1.day).round} days ago"
    end
  end
  
  def needs_reimport?
    last_imported_at.blank? || last_imported_at < 1.hour.ago
  end
  
  private
  
  def end_time_after_start_time
    return unless starts_at && ends_at
    
    if ends_at <= starts_at
      errors.add(:ends_at, 'must be after start time')
    end
  end
  
  def normalize_times
    # Ensure times are in UTC for consistent storage
    self.starts_at = starts_at&.utc
    self.ends_at = ends_at&.utc
  end
  
  def log_import
    Rails.logger.info "Imported external calendar event: #{external_event_id} for #{provider_display_name}"
  end

  def clear_staff_availability_cache
    AvailabilityService.clear_staff_availability_cache(calendar_connection.staff_member)
    calendar_connection.staff_member.touch
  end
end