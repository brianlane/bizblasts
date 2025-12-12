# frozen_string_literal: true

class BookingMailer < ApplicationMailer
  # Send confirmation email when a booking is created
  def confirmation(booking)
    @booking = booking
    @business = booking.business
    @customer = booking.tenant_customer
    @service = booking.service
    @staff_member = booking.staff_member

    # Video meeting data
    @video_meeting_url = booking.video_meeting_url
    @video_meeting_password = booking.video_meeting_password
    @video_meeting_provider = booking.video_meeting_provider_name
    @has_video_meeting = booking.has_video_meeting?
    # Check if video meeting is expected but still being created
    @video_meeting_pending = booking.video_meeting_video_pending? && booking.service&.video_meeting_enabled?

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

    # Video meeting data
    @video_meeting_url = booking.video_meeting_url
    @video_meeting_password = booking.video_meeting_password
    @video_meeting_provider = booking.video_meeting_provider_name
    @has_video_meeting = booking.has_video_meeting?
    # Check if video meeting is expected but still being created (rare for reminders, but possible)
    @video_meeting_pending = booking.video_meeting_video_pending? && booking.service&.video_meeting_enabled?

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

    # Video meeting data
    @video_meeting_url = booking.video_meeting_url
    @video_meeting_password = booking.video_meeting_password
    @video_meeting_provider = booking.video_meeting_provider_name
    @has_video_meeting = booking.has_video_meeting?
    # Check if video meeting is expected but still being created
    @video_meeting_pending = booking.video_meeting_video_pending? && booking.service&.video_meeting_enabled?

    mail(
      to: @customer.email,
      subject: "Subscription Booking Scheduled - #{@service.name}",
      from: @business.email,
      reply_to: @business.email
    )
  end

  # Send video meeting link after it's been created (follow-up to confirmation)
  def video_meeting_ready(booking)
    @booking = booking
    @business = booking.business
    @customer = booking.tenant_customer
    @service = booking.service
    @staff_member = booking.staff_member

    @video_meeting_url = booking.video_meeting_url
    @video_meeting_password = booking.video_meeting_password
    @video_meeting_provider = booking.video_meeting_provider_name

    # Use safe navigation in case service was deleted between meeting creation and email
    service_name = @service&.name || 'Appointment'

    mail(
      to: @customer.email,
      subject: "Your Video Meeting Link - #{service_name}",
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
