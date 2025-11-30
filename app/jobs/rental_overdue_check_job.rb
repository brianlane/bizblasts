# frozen_string_literal: true

class RentalOverdueCheckJob < ApplicationJob
  queue_as :default
  
  # This job checks for overdue rentals and sends notifications
  # It should be run periodically (e.g., every hour) via recurring schedule
  def perform
    Rails.logger.info("[RentalOverdueCheckJob] Starting overdue check")

    overdue_count = 0
    notification_count = 0
    error_count = 0

    # Find all rentals that are overdue (checked out or already marked overdue and past return time)
    RentalBooking.overdue_rentals.find_each do |booking|
      begin
        # If still checked_out, mark as overdue (first detection)
        if booking.status_checked_out?
          booking.mark_overdue!  # This changes status, adds note, and sends first notification
          overdue_count += 1
          notification_count += 1
        else
          # Already marked overdue - send daily reminder if not already sent today
          last_notification = booking.notes&.match(/Overdue notification sent: (\d{4}-\d{2}-\d{2})/)
          last_date = last_notification ? Date.parse(last_notification[1]) : nil

          if last_date != Date.current
            RentalMailer.overdue_notice(booking).deliver_later
            booking.update!(notes: [booking.notes, "Overdue notification sent: #{Date.current}"].compact.join("\n"))
            notification_count += 1
          end
        end
      rescue => e
        error_count += 1
        Rails.logger.error("[RentalOverdueCheckJob] Failed for booking #{booking.id} (#{booking.booking_number}): #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
        # Continue processing other bookings
      end
    end

    Rails.logger.info("[RentalOverdueCheckJob] Completed: #{overdue_count} marked overdue, #{notification_count} notifications sent, #{error_count} errors")
  end
end

