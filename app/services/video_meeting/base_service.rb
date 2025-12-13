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
      # If the access token is expired, we must refresh or fail fast.
      if connection.token_expired?
        unless connection.refresh_token.present?
          add_error(
            :token_expired,
            "Access token expired and no refresh token is available for #{connection.provider_name} connection (id=#{connection.id})"
          )
          return false
        end

        return refresh_access_token!
      end

      # Proactively refresh tokens that are about to expire to reduce provider API failures.
      if connection.token_expiring_soon? && connection.refresh_token.present?
        return refresh_access_token!
      end

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

    # Define exceptions that should be retried by the job layer
    RETRYABLE_EXCEPTIONS = [
      Net::ReadTimeout,
      Net::OpenTimeout,
      Faraday::TimeoutError,
      Errno::ECONNRESET,
      Errno::ECONNREFUSED,
      Errno::ETIMEDOUT
    ].freeze

    def handle_api_error(error)
      add_error(:api_error, error.message)
      Rails.logger.error("[#{self.class.name}] API Error: #{error.message}")
      Rails.logger.error(error.backtrace.first(10).join("\n")) if error.backtrace

      # Re-raise retryable network errors so the job layer can retry them
      # This allows CreateMeetingJob's retry_on declarations to work
      if RETRYABLE_EXCEPTIONS.any? { |klass| error.is_a?(klass) }
        raise error
      end
    end

    def refresh_access_token!
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
    rescue StandardError => e
      add_error(:refresh_failed, "Unexpected error refreshing token: #{e.message}")
      false
    end
  end
end
