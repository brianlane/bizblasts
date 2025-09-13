class BookingManager
  # This service handles operations related to bookings, including
  # creation, updates, and availability checking

  # Create a new booking with comprehensive error checking
  def self.create_booking(booking_params, business = nil)
    ActiveRecord::Base.transaction do
      # Create the booking with the appropriate business scope
      booking = business ? business.bookings.new : Booking.new
      
      # Ensure staff_member_id param is provided
      unless booking_params[:staff_member_id].present?
        booking.errors.add(:staff_member, "can't be blank")
        return [nil, booking.errors]
      end
      
      # Process date and time parameters if provided
      if booking_params[:date].present? && booking_params[:time].present?
        booking_params[:start_time] = process_datetime_params(booking_params[:date], booking_params[:time], (business || booking.business)&.time_zone || 'UTC')
      end
      
      # Filter and set the booking parameters
      filtered_attributes = filtered_params(booking_params)
      booking.assign_attributes(filtered_attributes)
      
      # Find or create customer if params include customer info but no tenant_customer_id
      if !booking_params[:tenant_customer_id].present? && 
          booking_params[:customer_name].present? && 
          booking_params[:customer_email].present?
        
        # Split customer name more intelligently
        name_parts = booking_params[:customer_name].strip.split(' ', 2)
        first_name = name_parts[0] || 'Unknown'
        last_name = name_parts[1] || 'Customer'
        
        customer = find_or_create_customer(
          business: business || booking.business,
          first_name: first_name,
          last_name: last_name,
          email: booking_params[:customer_email],
          phone: booking_params[:customer_phone]
        )
        
        if customer.nil?
          booking.errors.add(:base, "Could not create customer record")
          return [nil, booking.errors]
        end
        
        booking.tenant_customer = customer
      end
      
      # Calculate end_time based on service duration if not set
      if booking.start_time && !booking.end_time && booking.service&.duration
        # Check booking policy duration constraints for min/max
        policy = (business || booking.business)&.booking_policy
        duration_mins = booking.service.duration
        
        if policy.present?
          # Enforce minimum duration if needed
          if policy.min_duration_mins.present? && duration_mins < policy.min_duration_mins
            duration_mins = policy.min_duration_mins
            Rails.logger.info "[BookingManager] Adjusted duration to minimum policy value: #{duration_mins} minutes"
          end
          
          # Check max duration
          if policy.max_duration_mins.present? && duration_mins > policy.max_duration_mins
            booking.errors.add(:base, "Booking duration (#{duration_mins} minutes) exceeds the maximum allowed (#{policy.max_duration_mins} minutes)")
            return [nil, booking.errors]
          end
        end
        
        booking.end_time = booking.start_time + duration_mins.minutes
      end
      
      # Set default status if not specified
      booking.status ||= :pending
      
      # Set initial price based on service if not specified
      if booking.amount.nil? && booking.service&.price
        booking.amount = booking.service.price
        booking.original_amount = booking.service.price
        booking.discount_amount ||= 0
      end
      
      # Remove add-ons with quantity <= 0
      if booking.booking_product_add_ons
        booking.booking_product_add_ons = booking.booking_product_add_ons.reject { |a| a.quantity.to_i <= 0 }
      end
      
      # Ensure staff member is present
      if booking.staff_member.nil?
        booking.errors.add(:staff_member, "can't be blank")
        return [nil, booking.errors]
      end

      # Check availability for staff member
      staff_member = booking.staff_member
      unless AvailabilityService.is_available?(
        staff_member: staff_member,
        start_time: booking.start_time,
        end_time: booking.end_time
      )
        booking.errors.add(:base, "The selected time is not available for this staff member")
        return [nil, booking.errors]
      end
      
      # Check spots availability for experience services
      service = booking.service
      if service&.experience?
        requested = booking.quantity.to_i
        available = service.spots.to_i
        if available < requested
          booking.errors.add(:base, "Not enough spots available for this experience. Requested: #{requested}, Available: #{available}.")
          return [nil, booking.errors]
        end
      end
      
      # Validate booking (including quantity per-booking constraints)
      unless booking.valid?
        return [nil, booking.errors]
      end
      
      # Save the booking
      unless booking.save
        return [nil, booking.errors]
      end
      
      # --- Decrement spots for Experience services after successful booking ---
      if service&.experience?
        service.decrement!(:spots, booking.quantity.to_i)
        # Note: No need to explicitly save service here, decrement! handles it.
      end
      # --- End decrement logic ---
      
      # Handle confirmation emails
      if booking_params[:send_confirmation]
        # Placeholder for sending confirmation
        Rails.logger.info "[BookingManager] Send confirmation flag set for Booking ##{booking.id}"
        NotificationService.booking_confirmation(booking)
      end
      
      # Handle payment requirements
      if booking_params[:require_payment] && booking.amount.present? && booking.amount > 0
        # Use stripe_service to create a payment intent
        Rails.logger.info "[BookingManager] Require payment flag set for Booking ##{booking.id}"
        # payment_intent = StripeService.create_payment_intent(booking, booking.amount)
      end
      
      # Schedule reminders
      schedule_reminders(booking)
      
      [booking, nil] # Return the booking and nil for errors
    end
  rescue => e
    Rails.logger.error "[BookingManager] Error creating booking: #{e.message}\n#{e.backtrace.join("\n")}"
    [nil, OpenStruct.new(full_messages: ["An unexpected error occurred: #{e.message}"])]
  end
  
  # Update an existing booking with checks for availability
  def self.update_booking(booking, booking_params)
    ActiveRecord::Base.transaction do
      # Store original values for comparison after update
      original_start_time = booking.start_time
      original_end_time = booking.end_time
      original_status = booking.status
      original_quantity = booking.quantity # Store original quantity
      
      # Process date and time parameters if provided
      if booking_params[:date].present? && booking_params[:time].present?
        booking_params[:start_time] = process_datetime_params(booking_params[:date], booking_params[:time], booking.business&.time_zone || 'UTC')
      end
      
      # Calculate new end_time if start_time or service changed
      if (booking_params[:start_time] && booking_params[:start_time] != original_start_time) || 
         (booking_params[:service_id] && booking_params[:service_id] != booking.service_id)
        
        # Get the service - either updated or existing
        service_id = booking_params[:service_id] || booking.service_id
        service = Service.find_by(id: service_id)
        
        if service && service.duration
          new_start_time = booking_params[:start_time] || booking.start_time
          duration_mins = service.duration
          
          # Check booking policy duration constraints
          business = booking.business
          business.ensure_time_zone! if business.respond_to?(:ensure_time_zone!)
          policy = business&.booking_policy
          
          if policy.present?
            # Enforce minimum duration if needed
            if policy.min_duration_mins.present? && duration_mins < policy.min_duration_mins
              duration_mins = policy.min_duration_mins
              Rails.logger.info "[BookingManager] Adjusted duration to minimum policy value: #{duration_mins} minutes"
            end
            
            # Check max duration
            if policy.max_duration_mins.present? && duration_mins > policy.max_duration_mins
              booking.errors.add(:base, "Booking duration (#{duration_mins} minutes) exceeds the maximum allowed (#{policy.max_duration_mins} minutes)")
              return [nil, booking.errors]
            end
          end
          
          booking_params[:end_time] = new_start_time + duration_mins.minutes
        end
      end
      
      # First try to update attributes without saving to validate the parameters
      booking_copy = booking.dup
      booking_copy.assign_attributes(filtered_params(booking_params))
      
      # Remove add-ons with quantity <= 0
      if booking_copy.booking_product_add_ons
        booking_copy.booking_product_add_ons = booking_copy.booking_product_add_ons.reject { |a| a.quantity.to_i <= 0 }
      end
      
      # Check availability if time or staff changed
      if booking_params[:start_time] || booking_params[:end_time] || booking_params[:staff_member_id]
        start_time = booking_params[:start_time] || booking.start_time
        end_time = booking_params[:end_time] || booking.end_time
        staff_member_id = booking_params[:staff_member_id] || booking.staff_member_id
        staff_member = StaffMember.find_by(id: staff_member_id)
        
        unless staff_member && AvailabilityService.is_available?(
          staff_member: staff_member, 
          start_time: start_time, 
          end_time: end_time,
          exclude_booking_id: booking.id # Exclude this booking from conflict check
        )
          booking.errors.add(:base, "The selected time is not available for this staff member")
          return [nil, booking.errors]
        end
      end
      
      # Update the booking
      unless booking.update(filtered_params(booking_params))
        return [nil, booking.errors]
      end
      
      # --- Adjust spots for Experience services after successful update ---
      service = booking.service
      if service&.experience?
        quantity_change = booking.quantity.to_i - original_quantity.to_i

        if quantity_change > 0
          # If quantity increased, check if enough spots are available before decrementing
          if service.spots.nil? || service.spots < quantity_change
             # Rollback the booking update if not enough spots
            raise ActiveRecord::Rollback, "Not enough spots available to increase booking quantity."
          end
          service.decrement!(:spots, quantity_change)
        elsif quantity_change < 0
          # If quantity decreased, increment spots by the difference
          service.increment!(:spots, quantity_change.abs)
        end
        # Note: No need to explicitly save service here, increment!/decrement! handle it.
      end
      # --- End adjust spots logic ---
      
      # Send notifications based on changes
      if booking.saved_change_to_status?
        # Notify customer of status change
        Rails.logger.info "[BookingManager] Status changed from #{original_status} to #{booking.status} for Booking ##{booking.id}"
        NotificationService.booking_status_update(booking)
      end
      
      # Reschedule reminders if time changed
      if booking.saved_change_to_start_time?
        reschedule_reminders(booking)
      end
      
      [booking, nil] # Return the booking and nil for errors
    end
  rescue => e
    Rails.logger.error "[BookingManager] Error updating booking: #{e.message}"
    [nil, OpenStruct.new(full_messages: ["An unexpected error occurred: #{e.message}"])]
  end
  
  # Cancel a booking with optional reason and handle related tasks
  # Returns [success, error_message] - success is boolean, error_message is string or nil
  def self.cancel_booking(booking, reason = nil, notify = true, current_user: nil)
    # Check if current user is business manager/staff with override privileges
    business_override = current_user&.manager? || current_user&.staff?
    
    # Apply cancellation policy only for client users, not business managers
    unless business_override
      # Check cancellation policy
      business = booking.business
      business.ensure_time_zone! if business.respond_to?(:ensure_time_zone!)
      policy = business&.booking_policy
      cancellation_window_minutes = policy&.cancellation_window_mins
      if cancellation_window_minutes.present? && cancellation_window_minutes > 0
        Time.use_zone(business.time_zone || 'UTC') do
          local_now   = Time.zone.now
          # Use the booking's local_start_time method which properly converts UTC to business timezone
          local_start = booking.local_start_time
          cancellation_deadline = local_start - cancellation_window_minutes.minutes
          if local_now > cancellation_deadline
            # Convert minutes to hours for user-friendly display
            error_message = if cancellation_window_minutes >= 60 && cancellation_window_minutes % 60 == 0
              hours = cancellation_window_minutes / 60
              time_unit = hours == 1 ? "hour" : "hours"
              "Cannot cancel booking within #{hours} #{time_unit} of the start time."
            else
              "Cannot cancel booking within #{cancellation_window_minutes} minutes of the start time."
            end
            
            booking.errors.add(:base, error_message)
            Rails.logger.warn "[BookingManager] Attempted to cancel Booking ##{booking.id} within cancellation window."
            return [false, error_message] # Return both success status and error message
          end
        end
      end
    end

    ActiveRecord::Base.transaction do
      # Update booking status with audit trail
      booking.update!(
        status: :cancelled,
        cancellation_reason: reason.present? ? reason : (business_override ? "Cancelled by business manager (override)" : nil),
        cancelled_by: current_user&.id,
        manager_override: business_override
      )
      
      # Enhanced logging for audit trail
      if business_override
        Rails.logger.info "[BookingManager] Manager override cancellation for Booking ##{booking.id} by User ##{current_user.id} (#{current_user.email})"
      else
        Rails.logger.info "[BookingManager] Normal cancellation for Booking ##{booking.id} by User ##{current_user&.id || 'system'}"
      end
      
      if notify
        # Notify customer
        Rails.logger.info "[BookingManager] Booking ##{booking.id} cancelled with reason: #{reason || 'Not provided'}"
        # Send cancellation email
        begin
          NotificationService.booking_cancellation(booking)
          Rails.logger.info "[BookingManager] Cancellation email scheduled for Booking ##{booking.id}"
        rescue => e
          Rails.logger.error "[BookingManager] Failed to schedule cancellation email for Booking ##{booking.id}: #{e.message}"
        end
      end
      
      # Find associated invoice
      invoice = booking.invoice
      
      # Handle invoice based on payment status
      if invoice
        if invoice.payments.successful.exists?
          # Invoice has payments - process refund if applicable
          Rails.logger.info "[BookingManager] Processing refund for cancelled Booking ##{booking.id} via Invoice ##{invoice.id}"
          invoice.payments.successful.each do |payment|
            refund_success = payment.initiate_refund(reason: "booking_cancelled", user: current_user)

            if refund_success
              Rails.logger.info "[BookingManager] Refund processed for Payment ##{payment.id} (Booking ##{booking.id})"
              # Mark invoice as cancelled if all payments fully refunded
              if invoice.payments.where.not(status: :refunded).none?
                invoice.update!(status: :cancelled)
              end

              # Update order status if applicable - use helper method to ensure consistency
              if (order = invoice.order)
                order.check_and_update_refund_status!
              end
            else
              Rails.logger.error "[BookingManager] Failed to refund Payment ##{payment.id} for Booking ##{booking.id}: #{payment.errors.full_messages.join(', ')}"
            end
          end
        else
          # Invoice has no payments - cancel it since service won't be performed
          invoice.update!(status: :cancelled)
          Rails.logger.info "[BookingManager] Cancelled unpaid Invoice ##{invoice.invoice_number} for cancelled Booking ##{booking.id}"
        end
      end
      
      # --- Increment spots for Experience services upon cancellation ---
      service = booking.service
      if service&.experience?
        service.increment!(:spots, booking.quantity.to_i)
        # Note: No need to explicitly save service here, increment! handles it.
      end
      # --- End increment spots logic ---
      
      # Return success status and no error message on successful cancellation
      [true, nil]
    end
  rescue ActiveRecord::RecordInvalid => e
    # Log error and return false with error message if updates fail
    Rails.logger.error "[BookingManager] Failed to cancel Booking ##{booking.id}: #{e.message}"
    [false, "Failed to cancel booking: #{e.message}"]
  end
  
  # Check if a booking slot is available
  def self.available?(staff_member:, start_time:, end_time:, exclude_booking_id: nil)
    AvailabilityService.is_available?(
      staff_member: staff_member,
      start_time: start_time,
      end_time: end_time,
      exclude_booking_id: exclude_booking_id
    )
  end
  
  private
  
  # Process date and time strings into a DateTime object
  def self.process_datetime_params(date_str, time_str, zone = 'UTC')
    return nil if date_str.blank? || time_str.blank?

    Time.use_zone(zone) do
      begin
        date = Date.parse(date_str.to_s)

        # Handle different time string formats
        if time_str.to_s.include?(':')
          hour, minute = time_str.split(':').map(&:to_i)
        else
          time_int = time_str.to_i
          hour = time_int / 100
          minute = time_int % 100
        end

        hour = [[hour, 0].max, 23].min
        minute = [[minute, 0].max, 59].min

        Time.zone.local(date.year, date.month, date.day, hour, minute)
      rescue ArgumentError, TypeError => e
        Rails.logger.error "[BookingManager] Error parsing datetime: #{e.message} for date: #{date_str}, time: #{time_str}"
        nil
      end
    end
  end
  
  # Find an existing customer or create a new one
  def self.find_or_create_customer(business:, first_name:, last_name:, email:, phone: nil)
    return nil unless business && first_name.present? && last_name.present? && email.present?
    
    # Try to find an existing customer
    customer = business.tenant_customers.find_by(email: email)
    
    # Create a new customer if none exists
    unless customer
      customer = business.tenant_customers.new(
        first_name: first_name,
        last_name: last_name,
        email: email,
        phone: phone
      )
      
      return nil unless customer.save
    end
    
    customer
  end
  
  # Schedule booking reminders
  def self.schedule_reminders(booking)
    begin
    # Schedule reminder for 24 hours before booking
    reminder_time = booking.start_time - 24.hours
    BookingReminderJob.set(wait_until: reminder_time).perform_later(booking.id, '24h')
    
    # Schedule reminder for 1 hour before booking
    reminder_time = booking.start_time - 1.hour
    BookingReminderJob.set(wait_until: reminder_time).perform_later(booking.id, '1h')
      
      Rails.logger.info "[BookingManager] Scheduled reminders for Booking ##{booking.id}"
    rescue ActiveRecord::StatementInvalid => e
      # Handle case where SolidQueue tables don't exist
      if e.message.include?("solid_queue_jobs") && e.message.include?("does not exist")
        Rails.logger.warn "[BookingManager] SolidQueue tables not available. Skipping reminder scheduling."
        # Continue with booking creation - don't let missing reminders block the main flow
      else
        # For other database errors, re-raise to be handled by the caller
        raise
      end
    rescue StandardError => e
      # Log other errors but don't fail the entire booking process
      Rails.logger.error "[BookingManager] Failed to schedule reminders: #{e.message}"
    end
  end
  
  # Reschedule reminders for a booking
  def self.reschedule_reminders(booking)
    # In a real implementation, you would cancel existing reminders and schedule new ones
    # This is a simplified version
    schedule_reminders(booking)
  end
  
  # Filter params to only include allowed attributes
  def self.filtered_params(params)
    allowed_keys = %i[
      service_id staff_member_id tenant_customer_id
      notes status amount original_amount discount_amount
      start_time end_time quantity
      booking_product_add_ons_attributes tenant_customer_attributes
    ]
    
    # Convert params to a hash we can work with
    params_hash = params.is_a?(ActionController::Parameters) ? params.to_unsafe_h : params.to_h
    
    # Handle multi-parameter datetime attributes for start_time and end_time
    datetime_keys = params_hash.keys.select do |key| 
      key.to_s.start_with?('start_time(') || key.to_s.start_with?('end_time(')
    end
    
    # Gather all permitted keys including datetime multi-params
    filtered_hash = params_hash.slice(*allowed_keys)
    datetime_keys.each { |key| filtered_hash[key] = params_hash[key] }
    
    # Clean up and convert to proper parameter object
    if params.is_a?(ActionController::Parameters)
      ActionController::Parameters.new(filtered_hash).permit!
    else
      filtered_hash.symbolize_keys
    end
  end
end
