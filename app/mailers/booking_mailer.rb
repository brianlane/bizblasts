# frozen_string_literal: true

class BookingMailer < ApplicationMailer
  # Send confirmation email when a booking is created
  def confirmation(booking)
    @booking = booking
    @business = booking.business
    @customer = booking.tenant_customer
    @service = booking.service
    @staff_member = booking.staff_member
    
    mail(
      to: @customer.email,
      subject: "Booking Confirmation - #{@service.name}",
      from: @business.email
    )
  end
  
  # Send update notification when booking status changes
  def status_update(booking)
    @booking = booking
    @business = booking.business
    @customer = booking.tenant_customer
    @status = booking.status
    
    mail(
      to: @customer.email,
      subject: "Booking Status Update - #{@business.name}",
      reply_to: @business.email
    )
  end
  
  # Send cancellation notification when booking is cancelled
  def cancellation(booking)
    @booking = booking
    @business = booking.business
    @customer = booking.tenant_customer
    @reason = booking.cancellation_reason
    
    mail(
      to: @customer.email,
      subject: "Booking Cancelled - #{@business.name}",
      reply_to: @business.email
    )
  end
  
  # Send reminder before booking
  def reminder(booking, time_before)
    @booking = booking
    @business = booking.business
    @customer = booking.tenant_customer
    @time_before = time_before
    
    mail(
      to: @customer.email,
      subject: "Reminder: Your Upcoming Booking - #{@business.name}",
      reply_to: @business.email
    )
  end

  # Send payment reminder for unpaid invoices
  def payment_reminder(booking)
    @booking = booking
    @business = booking.business
    @customer = booking.tenant_customer
    @invoice = booking.invoice
    @tier = @business.tier
    
    # Tier-specific messaging
    @tier_benefits = case @tier
    when 'standard'
      "As a valued customer of our Standard tier business, you have extended payment windows."
    when 'premium'
      "As a valued customer of our Premium tier business, you enjoy flexible payment options."
    else
      ""
    end
    
    subject = if @booking.service.experience?
      "Payment Required: Experience Booking - #{@business.name}"
    else
      "Payment Reminder: Service Booking - #{@business.name}"
    end
    
    mail(
      to: @customer.email,
      subject: subject,
      reply_to: @business.email
    )
  end

  # Send subscription booking confirmation email to customer
  def subscription_booking_created(booking)
    @booking = booking
    @business = booking.business
    @customer = booking.tenant_customer
    @service = booking.service
    @staff_member = booking.staff_member
    @subscription = booking.customer_subscription
    
    mail(
      to: @customer.email,
      subject: "Subscription Booking Scheduled - #{@service.name}",
      from: @business.email,
      reply_to: @business.email
    )
  end

  # Add methods for testing purposes
  def deliver_later
    # This is just a mock method for testing
    true
  end

  def deliver_now
    # This is just a mock method for testing
    true
  end
end
