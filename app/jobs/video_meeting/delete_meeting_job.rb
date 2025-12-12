# frozen_string_literal: true

module VideoMeeting
  class DeleteMeetingJob < ApplicationJob
    queue_as :default

    # Retry on network errors with exponential backoff
    retry_on Net::ReadTimeout, Net::OpenTimeout, wait: :exponentially_longer, attempts: 3
    retry_on Faraday::TimeoutError, wait: :exponentially_longer, attempts: 3
    retry_on Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT, wait: :exponentially_longer, attempts: 3

    # Don't retry if the booking was deleted - meeting is already orphaned
    discard_on ActiveRecord::RecordNotFound

    def perform(booking_id, business_id)
      booking = Booking.find(booking_id)
      business = Business.find(business_id)

      # Skip if no video meeting exists
      unless booking.has_video_meeting?
        Rails.logger.info("[DeleteMeetingJob] Booking #{booking_id} has no video meeting to delete")
        return
      end

      ActsAsTenant.with_tenant(business) do
        coordinator = MeetingCoordinator.new(booking)
        success = coordinator.delete_meeting

        if success
          Rails.logger.info("[DeleteMeetingJob] Successfully deleted video meeting for booking #{booking_id}")
        else
          Rails.logger.warn("[DeleteMeetingJob] Failed to delete video meeting for booking #{booking_id}")
          coordinator.errors.each do |error|
            Rails.logger.warn("  #{error.attribute}: #{error.message}")
          end
          # Don't mark as failed - the meeting may have been manually deleted or the connection removed
          # Just clear the local data so we don't keep trying
          clear_booking_meeting_data(booking)
        end
      end
    end

    private

    def clear_booking_meeting_data(booking)
      booking.update!(
        video_meeting_id: nil,
        video_meeting_url: nil,
        video_meeting_host_url: nil,
        video_meeting_password: nil,
        video_meeting_provider: :video_none,
        video_meeting_status: :video_not_created
      )
    end
  end
end
