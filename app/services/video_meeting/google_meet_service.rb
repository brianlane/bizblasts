# frozen_string_literal: true

module VideoMeeting
  class GoogleMeetService < BaseService
    GOOGLE_CALENDAR_API_BASE = 'https://www.googleapis.com/calendar/v3'

    # Create a Google Meet meeting by creating a calendar event with conference data
    # Returns a hash with meeting details or nil on failure
    def create_meeting(booking)
      return nil unless ensure_valid_token!

      require 'google/apis/calendar_v3'

      calendar_service = Google::Apis::CalendarV3::CalendarService.new
      calendar_service.authorization = build_auth_client

      event = build_calendar_event(booking)

      begin
        # Create event with conferenceDataVersion to request Meet link
        result = calendar_service.insert_event(
          'primary',
          event,
          conference_data_version: 1,
          send_notifications: false
        )

        connection.mark_used!

        # Extract Google Meet link from conference data
        meet_url = extract_meet_url(result)

        {
          meeting_id: result.id,
          join_url: meet_url,
          host_url: meet_url, # Google Meet uses same URL for host and participants
          password: nil, # Google Meet doesn't use passwords
          provider: 'google_meet',
          calendar_event_id: result.id
        }
      rescue Google::Apis::ClientError => e
        add_error(:create_failed, "Failed to create Google Meet: #{e.message}")
        nil
      rescue Google::Apis::AuthorizationError => e
        add_error(:auth_error, "Google authorization failed: #{e.message}")
        connection.deactivate!
        nil
      rescue => e
        handle_api_error(e)
        nil
      end
    end

    # Delete a Google Meet meeting (deletes the calendar event)
    def delete_meeting(meeting_id)
      return false unless ensure_valid_token!

      require 'google/apis/calendar_v3'

      calendar_service = Google::Apis::CalendarV3::CalendarService.new
      calendar_service.authorization = build_auth_client

      begin
        calendar_service.delete_event('primary', meeting_id)
        true
      rescue Google::Apis::ClientError => e
        # 404 means already deleted, which is fine
        if e.status_code == 404
          true
        else
          add_error(:delete_failed, "Failed to delete Google Meet: #{e.message}")
          false
        end
      rescue => e
        handle_api_error(e)
        false
      end
    end

    # Get Google Meet meeting details
    def get_meeting(meeting_id)
      return nil unless ensure_valid_token!

      require 'google/apis/calendar_v3'

      calendar_service = Google::Apis::CalendarV3::CalendarService.new
      calendar_service.authorization = build_auth_client

      begin
        event = calendar_service.get_event('primary', meeting_id)
        meet_url = extract_meet_url(event)

        {
          meeting_id: event.id,
          topic: event.summary,
          start_time: event.start&.date_time,
          end_time: event.end&.date_time,
          join_url: meet_url,
          host_url: meet_url,
          status: event.status
        }
      rescue Google::Apis::ClientError => e
        add_error(:get_failed, "Failed to get Google Meet: #{e.message}")
        nil
      rescue => e
        handle_api_error(e)
        nil
      end
    end

    private

    def build_auth_client
      require 'googleauth'

      credentials = GoogleOauthCredentials.credentials

      Signet::OAuth2::Client.new(
        client_id: credentials[:client_id],
        client_secret: credentials[:client_secret],
        token_credential_uri: 'https://oauth2.googleapis.com/token',
        access_token: connection.access_token,
        refresh_token: connection.refresh_token,
        expires_at: connection.token_expires_at
      )
    end

    def build_calendar_event(booking)
      require 'google/apis/calendar_v3'

      business = booking.business
      timezone = business&.time_zone || 'America/Los_Angeles'

      event = Google::Apis::CalendarV3::Event.new(
        summary: format_meeting_topic(booking),
        description: format_meeting_description(booking),
        start: Google::Apis::CalendarV3::EventDateTime.new(
          date_time: booking.start_time.iso8601,
          time_zone: timezone
        ),
        end: Google::Apis::CalendarV3::EventDateTime.new(
          date_time: booking.end_time.iso8601,
          time_zone: timezone
        ),
        conference_data: Google::Apis::CalendarV3::ConferenceData.new(
          create_request: Google::Apis::CalendarV3::CreateConferenceRequest.new(
            request_id: SecureRandom.uuid,
            conference_solution_key: Google::Apis::CalendarV3::ConferenceSolutionKey.new(
              type: 'hangoutsMeet'
            )
          )
        )
      )

      # Add attendees if customer has email
      if booking.tenant_customer&.email.present?
        event.attendees = [
          Google::Apis::CalendarV3::EventAttendee.new(
            email: booking.tenant_customer.email,
            display_name: booking.tenant_customer.full_name
          )
        ]
      end

      event
    end

    def extract_meet_url(event)
      return nil unless event.conference_data

      # Look for Google Meet entry point
      entry_point = event.conference_data.entry_points&.find do |ep|
        ep.entry_point_type == 'video'
      end

      entry_point&.uri
    end
  end
end
