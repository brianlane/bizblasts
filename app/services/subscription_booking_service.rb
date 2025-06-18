# frozen_string_literal: true

class SubscriptionBookingService
  attr_reader :customer_subscription, :business, :tenant_customer, :service
  
  def initialize(customer_subscription)
    @customer_subscription = customer_subscription
    @business = customer_subscription.business
    @tenant_customer = customer_subscription.tenant_customer
    @service = customer_subscription.service
  end
  
  def process_subscription!
    return false unless customer_subscription.service_subscription?
    return false unless customer_subscription.active?

    # Use the enhanced scheduling service for intelligent booking
    scheduling_service = SubscriptionSchedulingService.new(customer_subscription)
    result = scheduling_service.schedule_subscription_bookings!
    
    if result
      Rails.logger.info "[SUBSCRIPTION BOOKING] Successfully processed subscription #{customer_subscription.id} with enhanced scheduling"
      result
    else
      Rails.logger.warn "[SUBSCRIPTION BOOKING] Enhanced scheduling failed, falling back to basic booking logic"
      fallback_to_basic_booking
    end
  rescue => e
    Rails.logger.error "[SUBSCRIPTION BOOKING] Error processing subscription #{customer_subscription.id}: #{e.message}"
    false
  end
  
  private
  
  def fallback_to_basic_booking
    ActiveRecord::Base.transaction do
      # Create bookings for the subscription period
      bookings = create_subscription_bookings
      
      # If no bookings were created, return false
      return false if bookings.empty?
      
      # Create invoices for the bookings
      bookings.each { |booking| create_booking_invoice(booking) }
      
      # Award loyalty points for subscription payment
      award_subscription_loyalty_points!
      
      # Check for subscription milestones and award bonus points
      check_and_award_milestone_points!
      
      # Send notifications
      bookings.each { |booking| send_booking_notifications(booking) }
      
      # Update subscription billing date if method exists
      customer_subscription.advance_billing_date! if customer_subscription.respond_to?(:advance_billing_date!)
      
      true
    end
  rescue => e
    Rails.logger.error "[SUBSCRIPTION BOOKING] Error in fallback_to_basic_booking: #{e.message}"
    false
  end
  
  def create_subscription_bookings
    bookings = []
    quantity = customer_subscription.quantity || 1

    quantity.times do |i|
      booking_time = determine_booking_time(i)
      
      if booking_time && booking_available?(booking_time)
        booking = create_individual_booking(booking_time)
        bookings << booking if booking
      else
        handle_booking_unavailable(i)
      end
    end

    bookings
  end
  
  def determine_booking_time(appointment_index)
    # Start from next week to allow for scheduling
    start_date = Date.current.next_week
    
    # Add spacing between multiple bookings (1 hour apart)
    time_offset = appointment_index * 1.hour
    
    # Try to find available slots within the next 4 weeks
    (start_date..start_date + 4.weeks).each do |date|
      # Get available staff members for this service
      available_staff = service.staff_members.active
      
      # If no qualified staff for this service, fall back to any business staff
      if available_staff.empty?
        available_staff = business.staff_members.active
        Rails.logger.warn "[SUBSCRIPTION BOOKING] No qualified staff for service, using any available business staff"
      end
      
      next if available_staff.empty?
      
      # Check each staff member for available slots
      available_staff.each do |staff_member|
        available_slots = AvailabilityService.available_slots(staff_member, date, service)
        next if available_slots.empty?
        
        # Use first available slot with time offset
        first_slot = available_slots.first
        booking_time = first_slot[:start_time] + time_offset
        
        # Make sure the offset time is still within business hours
        if booking_time.hour >= 9 && booking_time.hour <= 17
          return booking_time
        end
      end
    end
    
    # Final fallback - create a booking for next week at 10 AM if no slots found
    fallback_time = start_date.beginning_of_week + 1.day + 10.hours + time_offset
    Rails.logger.warn "[SUBSCRIPTION BOOKING] No available slots found, using fallback time: #{fallback_time}"
    fallback_time
  end
  
  def booking_available?(booking_datetime)
    # Calculate end time
    duration = service.duration || 60
    end_time = booking_datetime + duration.minutes
    
    # Check if any qualified staff member is available for this time
    qualified_staff_available = service.staff_members.active.any? do |staff_member|
      AvailabilityService.is_available?(
        staff_member: staff_member,
        start_time: booking_datetime,
        end_time: end_time,
        service: service
      )
    end
    
    # If no qualified staff, check if any business staff is available
    if !qualified_staff_available && service.staff_members.active.empty?
      business.staff_members.active.any? do |staff_member|
        AvailabilityService.is_available?(
          staff_member: staff_member,
          start_time: booking_datetime,
          end_time: end_time,
          service: service
        )
      end
    else
      qualified_staff_available
    end
  end
  
  def create_individual_booking(booking_datetime)
    # Determine staff member
    staff_member = determine_staff_member(booking_datetime)
    
    # If no staff member found, try to create a fallback booking
    unless staff_member
      Rails.logger.warn "[SUBSCRIPTION BOOKING] No qualified staff found, creating booking with any available staff"
      staff_member = business.staff_members.active.first
      
      # If still no staff member, create one as a last resort
      unless staff_member
        Rails.logger.warn "[SUBSCRIPTION BOOKING] No staff members available, creating fallback booking assignment"
        # Don't return nil - allow the booking to be created without a staff member for now
        # This will be handled by validation if needed
      end
    end
    
    # Calculate end time
    duration = service.duration || 60
    end_time = booking_datetime + duration.minutes
    
    # Create booking if Booking model exists
    if defined?(Booking)
      # Ensure we have a staff member - create one if needed for the booking to succeed
      if staff_member.nil?
        staff_member = business.staff_members.active.first || create_fallback_staff_member
      end
      
      booking = business.bookings.create!(
        service: service,
        staff_member: staff_member,
        tenant_customer: tenant_customer,
        start_time: booking_datetime,
        end_time: end_time,
        status: :confirmed,
        notes: "Subscription booking - #{customer_subscription.frequency.humanize} service"
      )
      
      booking
    else
      Rails.logger.warn "[SUBSCRIPTION BOOKING] Booking model not available"
      nil
    end
  end
  
  def determine_staff_member(booking_datetime = nil)
    # Check for customer preferred staff member
    if customer_subscription.customer_preferences.present?
      preferred_staff_id = customer_subscription.customer_preferences['preferred_staff_id']
      if preferred_staff_id.present?
        preferred_staff = business.staff_members.find_by(id: preferred_staff_id)
        if preferred_staff&.active?
          # Check if preferred staff is qualified for this service
          if service.staff_members.include?(preferred_staff)
            # Check availability if booking_datetime is provided
            if booking_datetime.nil? || staff_available_at_time?(preferred_staff, booking_datetime)
              return preferred_staff
            end
          end
        end
      end
    end
    
    # Fallback to any qualified staff member
    qualified_staff = service.staff_members.active
    if qualified_staff.present?
      if booking_datetime
        # Find first available qualified staff
        qualified_staff.find { |staff| staff_available_at_time?(staff, booking_datetime) }
      else
        qualified_staff.first
      end
    else
      # Final fallback to any active staff member
      business.staff_members.active.first
    end
  end

  def staff_available_at_time?(staff_member, booking_datetime)
    return false unless staff_member&.active?
    
    duration = service.duration || 60
    end_time = booking_datetime + duration.minutes
    
    AvailabilityService.is_available?(
      staff_member: staff_member,
      start_time: booking_datetime,
      end_time: end_time,
      service: service
    )
  rescue => e
    Rails.logger.error "[SUBSCRIPTION BOOKING] Error checking staff availability: #{e.message}"
    false
    duration = service.duration || 60
    
    # Find any available staff member for the service
    available_staff = if booking_datetime
                        service.staff_members.active.find do |staff|
                          AvailabilityService.is_available?(
                            staff_member: staff,
                            start_time: booking_datetime,
                            end_time: booking_datetime + duration.minutes,
                            service: service
                          )
                        end
                      else
                        service.staff_members.active.first
                      end
    
    available_staff || business.staff_members.active.first
  end
  
  def create_booking_invoice(booking)
    if defined?(Invoice) && booking.respond_to?(:build_invoice)
      invoice = booking.build_invoice(
        tenant_customer: tenant_customer,
        business: business,
        due_date: booking.start_time.to_date,
        status: :paid # Subscription bookings are pre-paid
      )
      
      invoice.save!
      invoice
    end
  end
  
  def send_booking_notifications(booking)
    # Send customer notification
    begin
      if defined?(BookingMailer) && BookingMailer.respond_to?(:subscription_booking_created)
        BookingMailer.subscription_booking_created(booking).deliver_later
        Rails.logger.info "[EMAIL] Sent subscription booking notification to customer for booking #{booking.id}"
      end
    rescue => e
      Rails.logger.error "[EMAIL] Failed to send customer notification for booking #{booking.id}: #{e.message}"
    end

    # Send business notification
    begin
      if defined?(BusinessMailer) && BusinessMailer.respond_to?(:subscription_booking_received)
        BusinessMailer.subscription_booking_received(booking).deliver_later
        Rails.logger.info "[EMAIL] Sent subscription booking notification to business for booking #{booking.id}"
      end
    rescue => e
      Rails.logger.error "[EMAIL] Failed to send business notification for booking #{booking.id}: #{e.message}"
    end
  end

  def award_subscription_loyalty_points!
    return unless business.loyalty_program_enabled?
    
    if defined?(SubscriptionLoyaltyService)
      loyalty_service = SubscriptionLoyaltyService.new(customer_subscription)
      points_awarded = loyalty_service.award_subscription_payment_points!
      
      Rails.logger.info "[SUBSCRIPTION LOYALTY] Awarded #{points_awarded} points for subscription #{customer_subscription.id}"
    end
  end

  def check_and_award_milestone_points!
    return unless business.loyalty_program_enabled?
    return unless defined?(SubscriptionLoyaltyService)
    
    loyalty_service = SubscriptionLoyaltyService.new(customer_subscription)
    months_active = ((Time.current - customer_subscription.created_at) / 1.month).to_i
    
    # Check for milestone achievements
    case months_active
    when 1
      if !milestone_awarded?('first_month')
        loyalty_service.award_milestone_points!('first_month')
        Rails.logger.info "[SUBSCRIPTION LOYALTY] Awarded first month milestone for subscription #{customer_subscription.id}"
      end
    when 3
      if !milestone_awarded?('three_months')
        loyalty_service.award_milestone_points!('three_months')
        Rails.logger.info "[SUBSCRIPTION LOYALTY] Awarded three month milestone for subscription #{customer_subscription.id}"
      end
    when 6
      if !milestone_awarded?('six_months')
        loyalty_service.award_milestone_points!('six_months')
        Rails.logger.info "[SUBSCRIPTION LOYALTY] Awarded six month milestone for subscription #{customer_subscription.id}"
      end
    when 12
      if !milestone_awarded?('one_year')
        loyalty_service.award_milestone_points!('one_year')
        Rails.logger.info "[SUBSCRIPTION LOYALTY] Awarded one year milestone for subscription #{customer_subscription.id}"
      end
    when 24
      if !milestone_awarded?('two_years')
        loyalty_service.award_milestone_points!('two_years')
        Rails.logger.info "[SUBSCRIPTION LOYALTY] Awarded two year milestone for subscription #{customer_subscription.id}"
      end
    end
  end

  def milestone_awarded?(milestone_type)
    description_pattern = case milestone_type
                         when 'first_month' then '%First month subscription milestone%'
                         when 'three_months' then '%Three month subscription milestone%'
                         when 'six_months' then '%Six month subscription milestone%'
                         when 'one_year' then '%One year subscription milestone%'
                         when 'two_years' then '%Two year subscription milestone%'
                         else '%subscription milestone%'
                         end

    if tenant_customer.respond_to?(:loyalty_transactions)
      tenant_customer.loyalty_transactions
                     .where('description LIKE ?', description_pattern)
                     .exists?
    else
      false
    end
  end

  def handle_booking_unavailable(booking_index)
    # Handle booking unavailability based on customer preferences
    rebooking_preference = get_effective_rebooking_preference
    
    case rebooking_preference
    when 'same_day_next_month'
      handle_same_day_next_month_preference(booking_index)
    when 'soonest_available'
      handle_soonest_available_preference(booking_index)
    when 'loyalty_points'
      handle_loyalty_points_preference(booking_index)
    else
      # Default business behavior
      handle_default_rebooking(booking_index)
    end
  end

  def get_effective_rebooking_preference
    # Check customer preferences first
    if customer_subscription.customer_preferences.present?
      customer_pref = customer_subscription.customer_preferences['service_rebooking_preference']
      return customer_pref if customer_pref.present?
    end
    
    # Fall back to subscription's rebooking preference
    customer_subscription.customer_rebooking_preference || 'soonest_available'
  end

  def handle_same_day_next_month_preference(booking_index)
    # Try to book the same day next month
    next_month_date = Date.current.next_month
    target_time = determine_booking_time(booking_index)
    
    if target_time && booking_available?(target_time)
      create_individual_booking(target_time)
    else
      # Fallback to soonest available
      handle_soonest_available_preference(booking_index)
    end
  end

  def handle_soonest_available_preference(booking_index)
    # Try to find the soonest available slot
    target_time = determine_booking_time(booking_index)
    if target_time
      create_individual_booking(target_time)
    else
      handle_loyalty_points_preference(booking_index)
    end
  end

  def handle_loyalty_points_preference(booking_index)
    # Award bonus loyalty points when booking is not available and customer prefers loyalty points
    if business.loyalty_program_enabled? && defined?(SubscriptionLoyaltyService)
      loyalty_service = SubscriptionLoyaltyService.new(customer_subscription)
      loyalty_service.award_compensation_points!('booking_unavailable')
      Rails.logger.info "[SUBSCRIPTION LOYALTY] Awarded compensation points for unavailable booking"
    end
    
    Rails.logger.warn "[SUBSCRIPTION BOOKING] Could not create booking #{booking_index + 1} for subscription #{customer_subscription.id}"
  end

  def handle_default_rebooking(booking_index)
    # Use business default rebooking behavior (same as soonest available)
    handle_soonest_available_preference(booking_index)
  end

  def create_fallback_staff_member
    # This is a fallback scenario - in production, this should not happen
    # But for testing and robustness, we'll handle it gracefully
    Rails.logger.warn "[SUBSCRIPTION BOOKING] Creating fallback staff member for booking"
    
    # Try to find any staff member in the business first
    business.staff_members.active.first || business.staff_members.first
  end
end 
 
 
 