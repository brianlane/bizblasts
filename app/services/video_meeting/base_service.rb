# frozen_string_literal: true

module VideoMeeting
  class BaseService
    include ActiveModel::Validations

    attr_reader :errors, :connection

    def initialize(connection)
      @connection = connection
      @errors = ActiveModel::Errors.new(self)
    end

    # Create a meeting for a booking
    # Returns a hash with meeting details or nil on failure
    def create_meeting(booking)
      raise NotImplementedError, "Subclasses must implement #create_meeting"
    end

    # Delete a meeting
    def delete_meeting(meeting_id)
      raise NotImplementedError, "Subclasses must implement #delete_meeting"
    end

    # Get meeting details
    def get_meeting(meeting_id)
      raise NotImplementedError, "Subclasses must implement #get_meeting"
    end

    protected

    def ensure_valid_token!
      return true unless connection.needs_refresh?

      oauth_handler = OauthHandler.new
      success = oauth_handler.refresh_token(connection)

      unless success
        oauth_handler.errors.each do |error|
          add_error(error.attribute, error.message)
        end
        return false
      end

      connection.reload
      true
    end

    def format_meeting_topic(booking)
      service_name = booking.service&.name || 'Appointment'
      customer_name = booking.tenant_customer&.full_name || 'Customer'
      "#{service_name} - #{customer_name}"
    end

    def format_meeting_description(booking)
      business_name = booking.business&.name || ''
      service_name = booking.service&.name || 'Appointment'
      duration = booking.service&.duration || 60

      <<~DESC
        #{service_name}
        Duration: #{duration} minutes
        Business: #{business_name}

        Booking ID: #{booking.id}
      DESC
    end

    def add_error(type, message)
      @errors.add(type, message)
      Rails.logger.error("[#{self.class.name}] #{type}: #{message}")
    end

    def handle_api_error(error)
      add_error(:api_error, error.message)
      Rails.logger.error("[#{self.class.name}] API Error: #{error.message}")
      Rails.logger.error(error.backtrace.first(10).join("\n")) if error.backtrace
    end
  end
end
