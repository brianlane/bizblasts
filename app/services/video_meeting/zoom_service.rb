# frozen_string_literal: true

module VideoMeeting
  class ZoomService < BaseService
    ZOOM_API_BASE = 'https://api.zoom.us/v2'

    # Create a Zoom meeting for a booking
    # Returns a hash with meeting details or nil on failure
    def create_meeting(booking)
      return nil unless ensure_valid_token!

      uri = URI.parse("#{ZOOM_API_BASE}/users/me/meetings")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.path)
      request['Authorization'] = "Bearer #{connection.access_token}"
      request['Content-Type'] = 'application/json'
      request.body = meeting_payload(booking).to_json

      begin
        response = http.request(request)
        data = JSON.parse(response.body)

        if response.code == '201'
          connection.mark_used!
          {
            meeting_id: data['id'].to_s,
            join_url: data['join_url'],
            host_url: data['start_url'],
            password: data['password'],
            provider: 'zoom'
          }
        else
          add_error(:create_failed, "Failed to create Zoom meeting: #{data['message'] || data['code']}")
          nil
        end
      rescue JSON::ParserError => e
        add_error(:parse_error, "Failed to parse Zoom response: #{e.message}")
        nil
      rescue => e
        handle_api_error(e)
        nil
      end
    end

    # Delete a Zoom meeting
    def delete_meeting(meeting_id)
      return false unless ensure_valid_token!

      uri = URI.parse("#{ZOOM_API_BASE}/meetings/#{meeting_id}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Delete.new(uri.path)
      request['Authorization'] = "Bearer #{connection.access_token}"

      begin
        response = http.request(request)

        if response.code == '204' || response.code == '404'
          true
        else
          data = JSON.parse(response.body) rescue {}
          add_error(:delete_failed, "Failed to delete Zoom meeting: #{data['message'] || response.code}")
          false
        end
      rescue => e
        handle_api_error(e)
        false
      end
    end

    # Get Zoom meeting details
    def get_meeting(meeting_id)
      return nil unless ensure_valid_token!

      uri = URI.parse("#{ZOOM_API_BASE}/meetings/#{meeting_id}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri.path)
      request['Authorization'] = "Bearer #{connection.access_token}"

      begin
        response = http.request(request)
        data = JSON.parse(response.body)

        if response.code == '200'
          {
            meeting_id: data['id'].to_s,
            topic: data['topic'],
            start_time: data['start_time'],
            duration: data['duration'],
            join_url: data['join_url'],
            host_url: data['start_url'],
            password: data['password'],
            status: data['status']
          }
        else
          add_error(:get_failed, "Failed to get Zoom meeting: #{data['message'] || data['code']}")
          nil
        end
      rescue => e
        handle_api_error(e)
        nil
      end
    end

    private

    def meeting_payload(booking)
      business = booking.business
      timezone = business&.time_zone || 'America/Los_Angeles'

      {
        topic: format_meeting_topic(booking),
        type: 2, # Scheduled meeting
        start_time: booking.start_time.iso8601,
        duration: booking.service&.duration || 60,
        timezone: timezone,
        agenda: format_meeting_description(booking),
        settings: {
          host_video: true,
          participant_video: true,
          join_before_host: false,
          mute_upon_entry: true,
          waiting_room: true,
          approval_type: 2, # No registration required
          audio: 'both',
          auto_recording: 'none'
        }
      }
    end
  end
end
