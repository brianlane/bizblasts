# frozen_string_literal: true

class RentalReminderJob < ApplicationJob
  queue_as :default
  
  # This job sends reminders for upcoming pickups and returns
  # It should be run daily (e.g., every morning at 8am) via recurring schedule
  def perform
    Rails.logger.info("[RentalReminderJob] Starting reminder job")

    pickup_count = 0
    return_count = 0
    error_count = 0

    # Send pickup reminders for tomorrow's pickups
    tomorrow_start = Date.tomorrow.beginning_of_day
    tomorrow_end = Date.tomorrow.end_of_day

    RentalBooking.status_deposit_paid.where(start_time: tomorrow_start..tomorrow_end).find_each do |booking|
      begin
        # Check if we already sent a pickup reminder today to prevent duplicates
        last_reminder = booking.notes&.match(/Pickup reminder sent: (\d{4}-\d{2}-\d{2})/)
        last_date = last_reminder ? Date.parse(last_reminder[1]) : nil

        if last_date != Date.current
          RentalMailer.pickup_reminder(booking).deliver_later
          SmsService.send_rental_pickup_reminder(booking)
          booking.update!(notes: [booking.notes, "Pickup reminder sent: #{Date.current}"].compact.join("\n"))
          pickup_count += 1
        end
      rescue => e
        error_count += 1
        Rails.logger.error("[RentalReminderJob] Failed to send pickup reminder for booking #{booking.id} (#{booking.booking_number}): #{e.message}")
        # Continue processing other bookings
      end
    end

    # Send return reminders based on business settings
    # Default is 24 hours before return time
    RentalBooking.status_checked_out.find_each do |booking|
      begin
        hours_before = booking.business.rental_reminder_hours_before || 24
        reminder_time = booking.end_time - hours_before.hours

        # Check if we're within the reminder window and haven't sent already
        if Time.current >= reminder_time && booking.end_time > Time.current
          last_reminder = booking.notes&.match(/Return reminder sent: (\d{4}-\d{2}-\d{2})/)
          last_date = last_reminder ? Date.parse(last_reminder[1]) : nil

          if last_date != Date.current
            RentalMailer.return_reminder(booking).deliver_later
            SmsService.send_rental_return_reminder(booking)
            booking.update!(notes: [booking.notes, "Return reminder sent: #{Date.current}"].compact.join("\n"))
            return_count += 1
          end
        end
      rescue => e
        error_count += 1
        Rails.logger.error("[RentalReminderJob] Failed to send return reminder for booking #{booking.id} (#{booking.booking_number}): #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
        # Continue processing other bookings
      end
    end

    Rails.logger.info("[RentalReminderJob] Completed: #{pickup_count} pickup reminders, #{return_count} return reminders sent, #{error_count} errors")
  end
end

