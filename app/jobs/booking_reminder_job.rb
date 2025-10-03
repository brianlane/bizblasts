class BookingReminderJob < ApplicationJob
  queue_as :mailers

  def perform(booking_id, reminder_type)
    booking = Booking.find_by(id: booking_id)
    
    # Skip if booking doesn't exist (deleted) or is cancelled
    return unless booking && booking.status != 'cancelled'
    
    # Skip if booking is in the past (this shouldn't happen but just in case)
    return if booking.start_time < Time.current
    
    # Send the reminder (email + SMS)
    NotificationService.booking_reminder(booking, reminder_type)

    # Log the reminder
    Rails.logger.info "[BookingReminderJob] Sent #{reminder_type} reminder for Booking ##{booking.id}"
  end
end
