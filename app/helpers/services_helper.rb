# frozen_string_literal: true

module ServicesHelper
  # Format event date and time for display with timezone
  # Returns nil if service is not an event or has no start time
  def format_event_datetime(service)
    return unless service.event? && service.event_starts_at.present?

    event_zone = ActiveSupport::TimeZone[service.business&.time_zone.presence || Time.zone.name] || Time.zone
    event_start = service.event_starts_at.in_time_zone(event_zone)

    event_start.strftime('%B %d, %Y at %l:%M %p').strip
  end

  # Format event date only (without time) for display
  def format_event_date(service)
    return unless service.event? && service.event_starts_at.present?

    event_zone = ActiveSupport::TimeZone[service.business&.time_zone.presence || Time.zone.name] || Time.zone
    event_start = service.event_starts_at.in_time_zone(event_zone)

    event_start.strftime('%B %d, %Y')
  end

  # Format event time only (without date) for display
  def format_event_time(service)
    return unless service.event? && service.event_starts_at.present?

    event_zone = ActiveSupport::TimeZone[service.business&.time_zone.presence || Time.zone.name] || Time.zone
    event_start = service.event_starts_at.in_time_zone(event_zone)

    event_start.strftime('%l:%M %p').strip
  end

  # Format event for brief display (e.g., in lists)
  # Example: "Jul 15, 2025 • 2:00 PM"
  def format_event_brief(service)
    return unless service.event? && service.event_starts_at.present?

    event_zone = ActiveSupport::TimeZone[service.business&.time_zone.presence || Time.zone.name] || Time.zone
    event_start = service.event_starts_at.in_time_zone(event_zone)

    event_start.strftime('%b %d, %Y • %l:%M %p').strip
  end
end
