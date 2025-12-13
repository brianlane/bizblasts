# frozen_string_literal: true

module VideoMeeting
  class MeetingCoordinator
    include ActiveModel::Validations

    # Network errors that should be retried by the job layer
    # These must stay in sync with CreateMeetingJob's retry_on declarations
    RETRYABLE_EXCEPTIONS = [
      Net::ReadTimeout,
      Net::OpenTimeout,
      Faraday::TimeoutError,
      Errno::ECONNRESET,
      Errno::ECONNREFUSED,
      Errno::ETIMEDOUT
    ].freeze

    attr_reader :errors, :booking

    def initialize(booking)
      @booking = booking
      @errors = ActiveModel::Errors.new(self)
    end

    # Class method for easy invocation from jobs
    def self.create_meeting_for_booking(booking)
      new(booking).create_meeting
    end

    # Create a video meeting for the booking
    # Returns true on success, false on failure
    def create_meeting
      return false unless validate_prerequisites

      # Get the appropriate service
      service = build_meeting_service
      return false unless service

      # Create the meeting
      meeting_data = service.create_meeting(booking)

      if meeting_data
        unless meeting_data[:meeting_id].present? && meeting_data[:join_url].present?
          add_error(
            :invalid_meeting_data,
            "Provider returned invalid meeting data (meeting_id/join_url missing) for booking #{booking.id}"
          )
          handle_service_errors(service)
          mark_booking_failed
          return false
        end

        update_booking_with_meeting(meeting_data)
        true
      else
        handle_service_errors(service)
        mark_booking_failed
        false
      end
    rescue *RETRYABLE_EXCEPTIONS => e
      # Let retryable network errors propagate to the job layer for retry
      Rails.logger.warn("[MeetingCoordinator] Retryable error (will be retried by job): #{e.class} - #{e.message}")
      raise
    rescue StandardError => e
      # Non-retryable errors should mark the booking as failed
      add_error(:unexpected_error, "Unexpected error creating meeting: #{e.message}")
      Rails.logger.error("[MeetingCoordinator] Unexpected error: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
      mark_booking_failed
      false
    end

    # Delete a video meeting for the booking
    def delete_meeting
      return true unless booking.has_video_meeting?

      connection = find_video_connection
      unless connection
        # Can't delete via API without connection, but still clear local data
        clear_booking_meeting_data
        return true
      end

      service = build_service_for_provider(connection)
      unless service
        # Can't delete via API without service, but still clear local data
        clear_booking_meeting_data
        return true
      end

      success = service.delete_meeting(booking.video_meeting_id)

      # Always clear booking meeting data - even if API call fails,
      # we don't want stale references to potentially deleted meetings
      clear_booking_meeting_data

      unless success
        handle_service_errors(service)
      end

      success
    end

    private

    def validate_prerequisites
      unless booking.service&.video_meeting_enabled?
        add_error(:service_not_enabled, "Service does not have video meetings enabled")
        return false
      end

      unless booking.staff_member.present?
        add_error(:no_staff_member, "Booking has no assigned staff member")
        return false
      end

      provider = determine_provider
      unless provider
        add_error(:no_provider, "Could not determine video meeting provider")
        return false
      end

      connection = find_video_connection
      unless connection
        add_error(:no_connection, "Staff member #{booking.staff_member.name} is not connected to #{provider_name(provider)}")
        mark_booking_failed
        return false
      end

      true
    end

    def build_meeting_service
      connection = find_video_connection
      return nil unless connection

      build_service_for_provider(connection)
    end

    def build_service_for_provider(connection)
      case connection.provider
      when 'zoom'
        ZoomService.new(connection)
      when 'google_meet'
        GoogleMeetService.new(connection)
      else
        add_error(:unsupported_provider, "Unsupported provider: #{connection.provider}")
        nil
      end
    end

    def determine_provider
      return nil unless booking.service

      case booking.service.video_provider
      when 'video_zoom'
        'zoom'
      when 'video_google_meet'
        'google_meet'
      else
        nil
      end
    end

    def find_video_connection
      provider = determine_provider
      return nil unless provider

      booking.staff_member.video_connection_for(provider)
    end

    def update_booking_with_meeting(meeting_data)
      provider_enum = case meeting_data[:provider]
                      when 'zoom' then :video_zoom
                      when 'google_meet' then :video_google_meet
                      else :video_none
                      end

      booking.update!(
        video_meeting_id: meeting_data[:meeting_id],
        video_meeting_url: meeting_data[:join_url],
        video_meeting_host_url: meeting_data[:host_url],
        video_meeting_password: meeting_data[:password],
        video_meeting_provider: provider_enum,
        video_meeting_status: :video_created
      )

      Rails.logger.info("[MeetingCoordinator] Created #{meeting_data[:provider]} meeting for booking #{booking.id}")
    end

    def clear_booking_meeting_data
      booking.update!(
        video_meeting_id: nil,
        video_meeting_url: nil,
        video_meeting_host_url: nil,
        video_meeting_password: nil,
        video_meeting_provider: :video_none,
        video_meeting_status: :video_not_created
      )
    end

    def mark_booking_failed
      booking.update_column(:video_meeting_status, Booking.video_meeting_statuses[:video_failed])
    end

    def handle_service_errors(service)
      service.errors.each do |error|
        add_error(error.attribute, error.message)
      end
    end

    def add_error(type, message)
      @errors.add(type, message)
      Rails.logger.error("[MeetingCoordinator] #{type}: #{message}")
    end

    def provider_name(provider)
      case provider
      when 'zoom' then 'Zoom'
      when 'google_meet' then 'Google Meet'
      else provider
      end
    end
  end
end
