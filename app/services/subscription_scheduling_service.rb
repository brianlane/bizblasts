# frozen_string_literal: true

class SubscriptionSchedulingService
  attr_reader :customer_subscription, :business, :tenant_customer, :service

  def initialize(customer_subscription)
    @customer_subscription = customer_subscription
    @business = customer_subscription.business
    @tenant_customer = customer_subscription.tenant_customer
    @service = customer_subscription.service
  end

  # Main method to schedule subscription bookings with intelligent logic
  def schedule_subscription_bookings!
    return false unless customer_subscription.service_subscription?
    return false unless customer_subscription.active?

    ActiveRecord::Base.transaction do
      # Calculate how many bookings to create based on frequency
      bookings_to_create = calculate_bookings_for_period
      
      # Create the bookings
      bookings = create_scheduled_bookings(bookings_to_create)
      
      if bookings.any?
        Rails.logger.info "[SUBSCRIPTION SCHEDULING] Created #{bookings.count} bookings for subscription #{customer_subscription.id}"
        true
      else
        Rails.logger.warn "[SUBSCRIPTION SCHEDULING] No bookings could be created for subscription #{customer_subscription.id}"
        false
      end
    end
  rescue => e
    Rails.logger.error "[SUBSCRIPTION SCHEDULING] Error scheduling subscription #{customer_subscription.id}: #{e.message}"
    false
  end

  def find_next_available_slot(preferred_date = nil)
    start_date = preferred_date || Date.current.next_week
    
    # Try to find available slots within the next 8 weeks
    (start_date..start_date + 8.weeks).each do |date|
      # Skip dates that don't match customer preferences
      next unless date_matches_preferences?(date)
      
      # Get available staff members for this service
      available_staff = service.staff_members.active
      next if available_staff.empty?
      
      # Check each staff member for available slots
      available_staff.each do |staff_member|
        available_slots = AvailabilityService.available_slots(staff_member, date, service)
        next if available_slots.empty?
        
        # Filter slots based on customer time preferences
        preferred_slots = filter_slots_by_time_preference(available_slots)
        
        # Use first preferred slot or fallback to first available
        first_slot = preferred_slots.first || available_slots.first
        if first_slot
          return {
            date: date,
            time: first_slot[:start_time],
            staff_member: staff_member,
            slot: first_slot
          }
        end
      end
    end
    
    nil # No available slots found
  end

  def reschedule_booking(booking, new_date = nil)
    return false unless booking.respond_to?(:id) && booking.id.present?
    
    # Check if booking belongs to this subscription's customer and service
    return false unless booking.tenant_customer == tenant_customer
    return false unless booking.service == service
    return false unless booking.business == business
    
    # Find next available slot
    next_slot = find_next_available_slot(new_date)
    return false unless next_slot
    
    # Update booking
    duration = service.duration || 60
    booking.update!(
      start_time: Time.zone.parse("#{next_slot[:date]} #{next_slot[:time].strftime('%H:%M')}"),
      end_time: Time.zone.parse("#{next_slot[:date]} #{next_slot[:time].strftime('%H:%M')}") + duration.minutes,
      staff_member: next_slot[:staff_member]
    )
    
    Rails.logger.info "[SUBSCRIPTION SCHEDULING] Rescheduled booking #{booking.id} to #{booking.start_time}"
    true
  rescue => e
    Rails.logger.error "[SUBSCRIPTION SCHEDULING] Error rescheduling booking #{booking.id}: #{e.message}"
    false
  end

  def check_upcoming_bookings
    # Get bookings for the next 2 weeks - simplified to work with existing schema
    if defined?(Booking) && business.respond_to?(:bookings)
      upcoming_bookings = business.bookings
                                 .where(tenant_customer: tenant_customer, service: service)
                                 .where(start_time: Time.current..2.weeks.from_now)
                                 .order(:start_time)
      
      upcoming_bookings.each do |booking|
        # Check if the booking is still valid (staff available, etc.)
        unless booking_still_valid?(booking)
          Rails.logger.warn "[SUBSCRIPTION SCHEDULING] Booking #{booking.id} is no longer valid, attempting to reschedule"
          reschedule_booking(booking)
        end
      end
    end
  end

  private

  def date_matches_preferences?(date)
    return true unless customer_subscription.customer_preferences.present?
    
    preferred_days = customer_subscription.customer_preferences['preferred_days']
    return true unless preferred_days.present?
    
    # Convert date to day of week (0=Sunday, 1=Monday, etc.)
    day_of_week = date.wday
    day_name = Date::DAYNAMES[day_of_week].downcase
    
    preferred_days.include?(day_name) || preferred_days.include?(day_of_week.to_s)
  end

  def filter_slots_by_time_preference(available_slots)
    return available_slots unless customer_subscription.customer_preferences.present?
    
    preferred_time = customer_subscription.customer_preferences['preferred_time']
    return available_slots unless preferred_time.present?
    
    case preferred_time.downcase
    when 'morning'
      available_slots.select { |slot| slot[:start_time].hour < 12 }
    when 'afternoon'
      available_slots.select { |slot| slot[:start_time].hour >= 12 && slot[:start_time].hour < 17 }
    when 'evening'
      available_slots.select { |slot| slot[:start_time].hour >= 17 }
    else
      available_slots
    end
  end

  def calculate_bookings_for_period
    case customer_subscription.frequency
    when 'weekly'
      customer_subscription.quantity || 1
    when 'monthly'
      customer_subscription.quantity || 1
    when 'quarterly'
      (customer_subscription.quantity || 1) * 3 # 3 months worth
    when 'annually'
      (customer_subscription.quantity || 1) * 12 # 12 months worth
    else
      1
    end
  end

  def create_scheduled_bookings(count)
    bookings = []
    current_date = Date.current.next_week
    
    count.times do |i|
      # Calculate the target date based on frequency
      target_date = calculate_target_date(current_date, i)
      
      # Find available slot for this date
      slot_info = find_next_available_slot(target_date)
      
      if slot_info
        booking = create_booking_from_slot(slot_info)
        bookings << booking if booking
        
        # Update current_date for next iteration
        current_date = slot_info[:date] + frequency_interval
      else
        Rails.logger.warn "[SUBSCRIPTION SCHEDULING] Could not find available slot for booking #{i + 1}"
      end
    end
    
    bookings
  end

  def calculate_target_date(base_date, index)
    case customer_subscription.frequency
    when 'weekly'
      base_date + (index * 1.week)
    when 'monthly'
      base_date + (index * 1.month)
    when 'quarterly'
      base_date + (index * 1.month) # Monthly bookings for quarterly subscription
    when 'annually'
      base_date + (index * 1.month) # Monthly bookings for annual subscription
    else
      base_date + (index * 1.week)
    end
  end

  def frequency_interval
    case customer_subscription.frequency
    when 'weekly'
      1.week
    when 'monthly'
      1.month
    when 'quarterly'
      1.month
    when 'annually'
      1.month
    else
      1.week
    end
  end

  def create_booking_from_slot(slot_info)
    duration = service.duration || 60
    start_time = Time.zone.parse("#{slot_info[:date]} #{slot_info[:time].strftime('%H:%M')}")
    end_time = start_time + duration.minutes
    
    # Create booking if Booking model exists
    if defined?(Booking)
      booking = business.bookings.create!(
        service: service,
        staff_member: slot_info[:staff_member],
        tenant_customer: tenant_customer,
        start_time: start_time,
        end_time: end_time,
        status: :confirmed,
        notes: "Scheduled subscription booking - #{customer_subscription.frequency.humanize}"
      )
      
      Rails.logger.info "[SUBSCRIPTION SCHEDULING] Created booking #{booking.id} for #{start_time}"
      booking
    else
      Rails.logger.warn "[SUBSCRIPTION SCHEDULING] Booking model not available"
      nil
    end
  rescue => e
    Rails.logger.error "[SUBSCRIPTION SCHEDULING] Error creating booking: #{e.message}"
    nil
  end

  def booking_still_valid?(booking)
    # Check if staff member is still available
    return false unless booking.staff_member&.active?
    
    # Check if staff member can still perform the service
    return false unless booking.staff_member.services.include?(booking.service)
    
    # Check availability using AvailabilityService
    AvailabilityService.is_available?(
      staff_member: booking.staff_member,
      start_time: booking.start_time,
      end_time: booking.end_time,
      service: booking.service,
      exclude_booking_id: booking.id
    )
  end

  # Helper methods for availability checking
  def time_slot_available?(time)
    duration = service.duration || 60
    end_time = time + duration.minutes
    
    # Check if any qualified staff member is available
    service.staff_members.active.any? do |staff|
      AvailabilityService.is_available?(
        staff_member: staff,
        start_time: time,
        end_time: end_time,
        service: service
      )
    end
  end

  def staff_available_at_time?(staff_member, time)
    duration = service.duration || 60
    end_time = time + duration.minutes
    
    AvailabilityService.is_available?(
      staff_member: staff_member,
      start_time: time,
      end_time: end_time,
      service: service
    )
  end

  def find_available_times_for_date(date)
    # Simplified implementation - return basic time slots
    slots = []
    
    # Generate time slots from 9 AM to 5 PM in 30-minute intervals
    (9..16).each do |hour|
      [0, 30].each do |minute|
        time = Time.zone.parse("#{date} #{hour}:#{minute.to_s.rjust(2, '0')}")
        
        # Check if any staff member is available for this slot
        if service.staff_members.active.any? { |staff| staff_available_at_time?(staff, time) }
          slots << time
        end
      end
    end

    slots
  end

  # Notification methods
  def send_booking_unavailable_notification
    begin
      if defined?(SubscriptionMailer) && SubscriptionMailer.respond_to?(:booking_unavailable)
        SubscriptionMailer.booking_unavailable(customer_subscription).deliver_later
        Rails.logger.info "[EMAIL] Sent booking unavailable notification for subscription #{customer_subscription.id}"
      end
    rescue => e
      Rails.logger.error "[EMAIL] Failed to send booking unavailable notification: #{e.message}"
    end
  end

  # Delegate methods to existing services
  def create_booking_invoice(booking)
    if defined?(Invoice) && booking.respond_to?(:build_invoice)
      invoice = booking.build_invoice(
        tenant_customer: tenant_customer,
        business: business,
        due_date: booking.start_time.to_date,
        status: :paid
      )
      
      invoice.save!
      invoice
    end
  end

  def send_booking_notifications(booking)
    begin
      if defined?(BookingMailer) && BookingMailer.respond_to?(:subscription_booking_created)
        BookingMailer.subscription_booking_created(booking).deliver_later
      end
      if defined?(BusinessMailer) && BusinessMailer.respond_to?(:subscription_booking_received)
        BusinessMailer.subscription_booking_received(booking).deliver_later
      end
      Rails.logger.info "[EMAIL] Sent booking notifications for booking #{booking.id}"
    rescue => e
      Rails.logger.error "[EMAIL] Failed to send booking notifications: #{e.message}"
    end
  end

  def award_subscription_loyalty_points!
    return unless business.loyalty_program_enabled?
    
    if defined?(SubscriptionLoyaltyService)
      SubscriptionLoyaltyService.new(customer_subscription).award_subscription_points!
    end
  end

  def check_and_award_milestone_points!
    return unless business.loyalty_program_enabled?
    
    if defined?(SubscriptionLoyaltyService)
      SubscriptionLoyaltyService.new(customer_subscription).check_and_award_milestone_points!
    end
  end
end 