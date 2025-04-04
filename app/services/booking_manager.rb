class BookingManager
  # This service handles operations related to bookings, including
  # creation, updates, and availability checking

  def self.create_booking(booking_params)
    ActiveRecord::Base.transaction do
      # Create the booking
      booking = Booking.new(booking_params)
      
      # Check if the bookable item is available
      bookable = booking.bookable
      unless bookable.available?(booking.start_time, booking.end_time)
        booking.errors.add(:base, "The selected time is not available")
        return [nil, booking.errors]
      end
      
      # Save the booking
      return [nil, booking.errors] unless booking.save
      
      # Send confirmation email or SMS if requested
      if booking.send_confirmation
        # Placeholder for sending confirmation
        # BookingMailer.confirmation(booking).deliver_later
      end
      
      # Set up payment if payment is required upfront
      if booking.require_payment && booking.amount.present? && booking.amount > 0
        # Use stripe_service to create a payment intent
        # payment_intent = StripeService.create_payment_intent(booking, booking.amount)
      end
      
      # Schedule reminders
      schedule_reminders(booking)
      
      [booking, nil]
    end
  end
  
  def self.update_booking(booking, booking_params)
    ActiveRecord::Base.transaction do
      # Check if new time is available, if time is being changed
      if booking_params[:start_time].present? || booking_params[:end_time].present?
        start_time = booking_params[:start_time] || booking.start_time
        end_time = booking_params[:end_time] || booking.end_time
        
        # Only check availability if the time has changed
        if start_time != booking.start_time || end_time != booking.end_time
          unless booking.bookable.available?(start_time, end_time)
            booking.errors.add(:base, "The selected time is not available")
            return [nil, booking.errors]
          end
        end
      end
      
      # Update the booking
      return [nil, booking.errors] unless booking.update(booking_params)
      
      # Reschedule reminders if time has changed
      if booking.saved_change_to_start_time?
        reschedule_reminders(booking)
      end
      
      # Notify customer if needed
      if booking.saved_change_to_status?
        # Placeholder for sending notification
        # BookingMailer.status_update(booking).deliver_later
      end
      
      [booking, nil]
    end
  end
  
  def self.cancel_booking(booking, reason = nil)
    ActiveRecord::Base.transaction do
      # Update booking status
      booking.cancel!
      
      # Record cancellation reason if provided
      booking.update(cancellation_reason: reason) if reason.present?
      
      # Notify customer
      # BookingMailer.cancellation(booking).deliver_later
      
      # Process refund if applicable
      if booking.payments.successful.exists?
        # Placeholder for refund processing
        # booking.payments.successful.each do |payment|
        #   StripeService.refund_payment(payment)
        # end
      end
      
      true
    end
  end
  
  private
  
  def self.schedule_reminders(booking)
    # Schedule reminder for 24 hours before appointment
    reminder_time = booking.start_time - 24.hours
    BookingReminderJob.set(wait_until: reminder_time).perform_later(booking.id, '24h')
    
    # Schedule reminder for 1 hour before appointment
    reminder_time = booking.start_time - 1.hour
    BookingReminderJob.set(wait_until: reminder_time).perform_later(booking.id, '1h')
  end
  
  def self.reschedule_reminders(booking)
    # In a real implementation, you would cancel existing reminders and schedule new ones
    # This is a simplified version
    schedule_reminders(booking)
  end
end
