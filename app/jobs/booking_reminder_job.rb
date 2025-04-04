class BookingReminderJob < ApplicationJob
  queue_as :reminders

  def perform(booking_id, timeframe = '24h')
    booking = Booking.find_by(id: booking_id)
    return unless booking
    
    # Skip if booking is cancelled or completed
    return if booking.cancelled? || booking.completed? || booking.no_show?
    
    # Skip if the booking start time has already passed
    return if booking.start_time < Time.current
    
    # Determine message type based on timeframe
    case timeframe
    when '24h'
      # 24-hour reminder
      send_24h_reminder(booking)
    when '1h'
      # 1-hour reminder
      send_1h_reminder(booking)
    else
      # Generic reminder
      send_generic_reminder(booking)
    end
    
    # Mark that reminder was sent
    booking.update(reminder_sent_at: Time.current)
  end
  
  private
  
  def send_24h_reminder(booking)
    # Send email reminder
    # In a real implementation, this would use ActionMailer
    # BookingMailer.reminder_email(booking, '24h').deliver_later
    
    # Send SMS reminder if customer has a phone number
    if booking.customer.phone.present?
      SmsService.send_booking_reminder(booking, '24h')
    end
    
    # Log the reminder
    Rails.logger.info "24-hour reminder sent for booking ##{booking.id} at #{Time.current}"
  end
  
  def send_1h_reminder(booking)
    # For 1-hour reminders, we'll just send SMS to be less intrusive
    if booking.customer.phone.present?
      SmsService.send_booking_reminder(booking, '1h')
    end
    
    # Log the reminder
    Rails.logger.info "1-hour reminder sent for booking ##{booking.id} at #{Time.current}"
  end
  
  def send_generic_reminder(booking)
    # Send email reminder
    # BookingMailer.reminder_email(booking, 'generic').deliver_later
    
    # Send SMS reminder if customer has a phone number
    if booking.customer.phone.present?
      SmsService.send_booking_reminder(booking, 'generic')
    end
    
    # Log the reminder
    Rails.logger.info "Generic reminder sent for booking ##{booking.id} at #{Time.current}"
  end
end
