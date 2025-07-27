# frozen_string_literal: true

module Calendar
  class BaseService
    include ActiveModel::Validations
    
    attr_reader :calendar_connection, :errors
    
    def initialize(calendar_connection)
      @calendar_connection = calendar_connection
      @errors = ActiveModel::Errors.new(self)
    end
    
    # Abstract methods to be implemented by subclasses
    def create_event(booking)
      raise NotImplementedError, "Subclass must implement create_event"
    end
    
    def update_event(booking, external_event_id)
      raise NotImplementedError, "Subclass must implement update_event"
    end
    
    def delete_event(external_event_id)
      raise NotImplementedError, "Subclass must implement delete_event"
    end
    
    def import_events(start_date, end_date)
      raise NotImplementedError, "Subclass must implement import_events"
    end
    
    def refresh_access_token
      raise NotImplementedError, "Subclass must implement refresh_access_token"
    end
    
    protected
    
    # Common helper methods
    
    def with_error_handling
      yield
    rescue => e
      handle_api_error(e)
      nil
    end
    
    def handle_api_error(error)
      case error
      when Net::TimeoutError, Timeout::Error
        add_error(:timeout, "Request timed out. Please try again.")
      when Net::HTTPUnauthorized, Signet::AuthorizationError
        add_error(:unauthorized, "Calendar authorization expired. Please reconnect.")
        deactivate_connection
      when Net::HTTPForbidden
        add_error(:forbidden, "Insufficient permissions for calendar access.")
      when Net::HTTPTooManyRequests
        add_error(:rate_limited, "Rate limit exceeded. Please try again later.")
      when Net::HTTPBadRequest
        add_error(:bad_request, "Invalid request: #{error.message}")
      when Net::HTTPServerError
        add_error(:server_error, "Calendar service temporarily unavailable.")
      else
        add_error(:unknown, "Calendar sync failed: #{error.message}")
      end
      
      log_error(error)
    end
    
    def add_error(type, message)
      @errors.add(type, message)
      Rails.logger.error("[#{self.class.name}] #{type}: #{message}")
    end
    
    def log_error(error)
      Rails.logger.error([
        "[#{self.class.name}] Error: #{error.class.name}",
        "Message: #{error.message}",
        "Backtrace: #{error.backtrace&.first(5)&.join('\n')}"
      ].join('\n'))
    end
    
    def deactivate_connection
      calendar_connection.deactivate! if calendar_connection.active?
    end
    
    def format_booking_for_calendar(booking)
      {
        summary: booking_summary(booking),
        description: booking_description(booking),
        start_time: booking.start_time,
        end_time: booking.end_time,
        location: booking_location(booking),
        attendees: booking_attendees(booking)
      }
    end
    
    def booking_summary(booking)
      parts = []
      parts << booking.service_name if booking.service_name
      parts << "with #{booking.customer_full_name}" if booking.customer_full_name
      parts.join(' ')
    end
    
    def booking_description(booking)
      lines = []
      lines << "Service: #{booking.service_name}" if booking.service_name
      lines << "Customer: #{booking.customer_full_name}" if booking.customer_full_name
      lines << "Phone: #{booking.tenant_customer&.phone}" if booking.tenant_customer&.phone
      lines << "Email: #{booking.customer_email}" if booking.customer_email
      lines << "Notes: #{booking.notes}" if booking.notes.present?
      lines << "Booking ID: #{booking.id}"
      lines.join('\n')
    end
    
    def booking_location(booking)
      # Default to business address or empty string
      booking.business&.address || ''
    end
    
    def booking_attendees(booking)
      attendees = []
      
      # Add customer email if available
      if booking.customer_email.present?
        attendees << {
          email: booking.customer_email,
          display_name: booking.customer_full_name,
          response_status: 'accepted'
        }
      end
      
      # Add staff member email
      if calendar_connection.staff_member&.email.present?
        attendees << {
          email: calendar_connection.staff_member.email,
          display_name: calendar_connection.staff_member.name,
          response_status: 'accepted',
          organizer: true
        }
      end
      
      attendees
    end
    
    def retry_with_backoff(max_retries: 3, base_delay: 1)
      retries = 0
      begin
        yield
      rescue => e
        retries += 1
        if retries <= max_retries && retryable_error?(e)
          delay = base_delay * (2 ** (retries - 1))
          Rails.logger.info("Retrying in #{delay} seconds (attempt #{retries}/#{max_retries})")
          sleep(delay)
          retry
        else
          raise e
        end
      end
    end
    
    def retryable_error?(error)
      case error
      when Net::TimeoutError, Timeout::Error
        true
      when Net::HTTPTooManyRequests
        true
      when Net::HTTPServerError
        true
      else
        false
      end
    end
    
    def validate_booking(booking)
      unless booking.is_a?(Booking)
        add_error(:invalid_booking, "Invalid booking object")
        return false
      end
      
      unless booking.start_time && booking.end_time
        add_error(:invalid_times, "Booking must have start and end times")
        return false
      end
      
      unless booking.start_time < booking.end_time
        add_error(:invalid_time_order, "Start time must be before end time")
        return false
      end
      
      true
    end
    
    def validate_connection
      unless calendar_connection.active?
        add_error(:inactive_connection, "Calendar connection is not active")
        return false
      end
      
      if calendar_connection.oauth_provider? && calendar_connection.token_expired?
        if calendar_connection.needs_refresh?
          refresh_result = refresh_access_token
          unless refresh_result
            add_error(:expired_token, "Calendar authorization expired. Please reconnect.")
            return false
          end
        else
          add_error(:expired_token, "Calendar authorization expired. Please reconnect.")
          return false
        end
      end
      
      true
    end
    
    def log_sync_attempt(mapping, action, outcome, message = nil, metadata = {})
      CalendarSyncLog.log_sync_attempt(mapping, action, outcome, message, metadata)
    end
    
    def business_timezone
      calendar_connection.business&.time_zone || 'UTC'
    end
    
    def convert_to_business_timezone(time)
      time&.in_time_zone(business_timezone)
    end
  end
end