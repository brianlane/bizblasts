# frozen_string_literal: true

module VideoMeeting
  class CreateMeetingJob < ApplicationJob
    queue_as :default

    # Retry on network errors with exponential backoff
    # These must match the RETRYABLE_EXCEPTIONS in BaseService that are re-raised
    retry_on Net::ReadTimeout, Net::OpenTimeout, wait: :exponentially_longer, attempts: 3
    retry_on Faraday::TimeoutError, wait: :exponentially_longer, attempts: 3
    retry_on Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT, wait: :exponentially_longer, attempts: 3

    # Don't retry if the booking was deleted
    discard_on ActiveRecord::RecordNotFound

    def perform(booking_id)
      booking = Booking.find(booking_id)

      # Skip if meeting already created or not needed
      return if booking.video_meeting_video_created?

      # Skip if booking is no longer confirmed (e.g., was cancelled after job was enqueued)
      unless booking.confirmed?
        Rails.logger.info(
          "[CreateMeetingJob] Booking #{booking_id} is no longer confirmed (status: #{booking.status}). Skipping video meeting creation."
        )
        return
      end

      unless booking.video_meeting_required?
        # If the booking was marked pending when enqueued but prerequisites changed (e.g. connection removed),
        # don't leave it stuck in pending forever.
        if booking.video_meeting_video_pending?
          Rails.logger.warn(
            "[CreateMeetingJob] Booking #{booking_id} is no longer eligible for a video meeting (missing connection/staff). Marking failed."
          )
          booking.update_column(:video_meeting_status, Booking.video_meeting_statuses[:video_failed])
        end
        return
      end

      ActsAsTenant.with_tenant(booking.business) do
        coordinator = MeetingCoordinator.new(booking)
        success = coordinator.create_meeting

        if success
          # Send follow-up email with the video meeting link
          # This ensures customers get the link even though the confirmation email was sent before it was ready
          send_video_meeting_notification(booking)
        else
          Rails.logger.error("[CreateMeetingJob] Failed to create meeting for booking #{booking_id}")
          coordinator.errors.each do |error|
            Rails.logger.error("  #{error.attribute}: #{error.message}")
          end
        end
      end
    end

    private

    def send_video_meeting_notification(booking)
      return unless booking.tenant_customer&.email.present?

      BookingMailer.video_meeting_ready(booking).deliver_later
      Rails.logger.info("[CreateMeetingJob] Sent video meeting link email for booking #{booking.id}")
    rescue => e
      # Don't fail the job if email sending fails - the meeting is already created
      Rails.logger.error("[CreateMeetingJob] Failed to send video meeting email for booking #{booking.id}: #{e.message}")
    end
  end
end
