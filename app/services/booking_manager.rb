class BookingManager
  # This service handles operations related to bookings, including
  # creation, updates, and availability checking

  def self.create_booking(booking_params)
    ActiveRecord::Base.transaction do
      # Create the booking
      booking = Booking.new(booking_params)
      
      # Corrected: Check availability using staff_member
      staff_member = StaffMember.find(booking.staff_member_id) if booking.staff_member_id
      unless staff_member && staff_member.available?(booking.start_time, booking.end_time)
        booking.errors.add(:base, "The selected time is not available for this staff member")
        return [nil, booking.errors]
      end
      
      # Save the booking
      unless booking.save
        return [nil, booking.errors]
      end
      
      # Check flags from the params hash, not the booking object
      if booking_params[:send_confirmation]
        # Placeholder for sending confirmation
        Rails.logger.info "[BookingManager] Send confirmation flag set for Booking ##{booking.id}"
        # BookingMailer.confirmation(booking).deliver_later
      end
      
      # Check flags from the params hash
      if booking_params[:require_payment] && booking.amount.present? && booking.amount > 0
        # Use stripe_service to create a payment intent
        Rails.logger.info "[BookingManager] Require payment flag set for Booking ##{booking.id}"
        # payment_intent = StripeService.create_payment_intent(booking, booking.amount)
      end
      
      # Schedule reminders
      schedule_reminders(booking)
      
      [booking, nil]
    end
  end
  
  def self.update_booking(booking, booking_params)
    ActiveRecord::Base.transaction do
      # Corrected: Check availability using staff_member
      staff_member = booking.staff_member
      start_time = booking_params[:start_time] || booking.start_time
      end_time = booking_params[:end_time] || booking.end_time
      
      if start_time != booking.start_time || end_time != booking.end_time
        unless staff_member && staff_member.available?(start_time, end_time)
          booking.errors.add(:base, "The selected time is not available for this staff member")
          return [nil, booking.errors]
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
      booking.update!(status: :cancelled) # Use update! to catch potential errors
      
      # Record cancellation reason if provided
      booking.update!(cancellation_reason: reason) if reason.present?
      
      # Notify customer (Placeholder)
      # BookingMailer.cancellation(booking).deliver_later
      
      # Find associated invoice
      invoice = booking.invoice
      
      # Process refund if applicable (via Invoice)
      if invoice && invoice.payments.successful.exists?
        # Placeholder for refund processing
        Rails.logger.info "[BookingManager] Processing refund for cancelled Booking ##{booking.id} via Invoice ##{invoice.id}"
        # invoice.payments.successful.each do |payment|
        #   StripeService.refund_payment(payment)
        # end
      end
      
      true # Return true on success
    end
  rescue ActiveRecord::RecordInvalid => e
    # Log error and return false if updates fail
    Rails.logger.error "[BookingManager] Failed to cancel Booking ##{booking.id}: #{e.message}"
    false 
  end
  
  private
  
  def self.schedule_reminders(booking)
    # Schedule reminder for 24 hours before booking
    reminder_time = booking.start_time - 24.hours
    BookingReminderJob.set(wait_until: reminder_time).perform_later(booking.id, '24h')
    
    # Schedule reminder for 1 hour before booking
    reminder_time = booking.start_time - 1.hour
    BookingReminderJob.set(wait_until: reminder_time).perform_later(booking.id, '1h')
  end
  
  def self.reschedule_reminders(booking)
    # In a real implementation, you would cancel existing reminders and schedule new ones
    # This is a simplified version
    schedule_reminders(booking)
  end
end
