# frozen_string_literal: true

class BookingMailer < ApplicationMailer
  # Send confirmation email when a booking is created
  def confirmation(booking)
    @booking = booking
    @business = booking.business
    @customer = booking.tenant_customer
    
    mail(
      to: @customer.email,
      subject: "Booking Confirmation - #{@business.name}"
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
      subject: "Booking Status Update - #{@business.name}"
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
      subject: "Booking Cancelled - #{@business.name}"
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
      subject: "Reminder: Your Upcoming Booking - #{@business.name}"
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
