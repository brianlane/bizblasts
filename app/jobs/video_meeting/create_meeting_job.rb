# frozen_string_literal: true

module VideoMeeting
  class CreateMeetingJob < ApplicationJob
    queue_as :default

    # Retry on network errors with exponential backoff
    retry_on Net::ReadTimeout, Net::OpenTimeout, wait: :exponentially_longer, attempts: 3
    retry_on Faraday::TimeoutError, wait: :exponentially_longer, attempts: 3

    # Don't retry if the booking was deleted
    discard_on ActiveRecord::RecordNotFound

    def perform(booking_id)
      booking = Booking.find(booking_id)

      # Skip if meeting already created or not needed
      return if booking.video_meeting_video_created?
      return unless booking.video_meeting_required?

      ActsAsTenant.with_tenant(booking.business) do
        coordinator = MeetingCoordinator.new(booking)
        success = coordinator.create_meeting

        unless success
          Rails.logger.error("[CreateMeetingJob] Failed to create meeting for booking #{booking_id}")
          coordinator.errors.each do |error|
            Rails.logger.error("  #{error.attribute}: #{error.message}")
          end
        end
      end
    end
  end
end
