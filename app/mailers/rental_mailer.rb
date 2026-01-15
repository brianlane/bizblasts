# frozen_string_literal: true

class RentalMailer < ApplicationMailer
  # Booking confirmation - sent when booking is created
  def booking_confirmation(rental_booking)
    @rental_booking = rental_booking
    @business = rental_booking.business
    @customer = rental_booking.tenant_customer
    @rental = rental_booking.product
    
    mail(
      to: @customer.email,
      subject: "Rental Booking Confirmation - #{@business.name}",
      from: branding_from(@business)
    )
  end
  
  # Deposit paid confirmation - sent when security deposit is paid
  def deposit_paid_confirmation(rental_booking)
    @rental_booking = rental_booking
    @business = rental_booking.business
    @customer = rental_booking.tenant_customer
    @rental = rental_booking.product
    
    mail(
      to: @customer.email,
      subject: "Deposit Received - Your Rental is Confirmed! - #{@business.name}",
      from: branding_from(@business)
    )
  end
  
  # Pickup reminder - sent before pickup time
  def pickup_reminder(rental_booking)
    @rental_booking = rental_booking
    @business = rental_booking.business
    @customer = rental_booking.tenant_customer
    @rental = rental_booking.product
    
    mail(
      to: @customer.email,
      subject: "Reminder: Pickup Tomorrow - #{@rental.name}",
      from: branding_from(@business)
    )
  end
  
  # Return reminder - sent before return deadline
  def return_reminder(rental_booking)
    @rental_booking = rental_booking
    @business = rental_booking.business
    @customer = rental_booking.tenant_customer
    @rental = rental_booking.product
    
    mail(
      to: @customer.email,
      subject: "Reminder: Return Due Tomorrow - #{@rental.name}",
      from: branding_from(@business)
    )
  end
  
  # Overdue notice - sent when rental is overdue
  def overdue_notice(rental_booking)
    @rental_booking = rental_booking
    @business = rental_booking.business
    @customer = rental_booking.tenant_customer
    @rental = rental_booking.product
    
    mail(
      to: @customer.email,
      subject: "OVERDUE: Please Return Your Rental Immediately - #{@business.name}",
      from: branding_from(@business)
    )
  end
  
  # Completion and refund confirmation
  def completion_confirmation(rental_booking)
    @rental_booking = rental_booking
    @business = rental_booking.business
    @customer = rental_booking.tenant_customer
    @rental = rental_booking.product
    
    mail(
      to: @customer.email,
      subject: "Rental Completed - Deposit Refund Processed - #{@business.name}",
      from: branding_from(@business)
    )
  end
  
  # Cancellation confirmation
  def cancellation_confirmation(rental_booking)
    @rental_booking = rental_booking
    @business = rental_booking.business
    @customer = rental_booking.tenant_customer
    @rental = rental_booking.product
    
    mail(
      to: @customer.email,
      subject: "Rental Booking Cancelled - #{@business.name}",
      from: branding_from(@business)
    )
  end
  
  # Notify business of new booking
  def new_booking_notification(rental_booking)
    @rental_booking = rental_booking
    @business = rental_booking.business
    @customer = rental_booking.tenant_customer
    @rental = rental_booking.product
    
    # Find manager emails
    manager_emails = @business.users.where(role: :manager).pluck(:email)
    
    # Return a no-op mail object if no managers to avoid NoMethodError on .deliver_later
    return mail(to: nil, subject: "Skip - No Recipients", from: branding_from(@business)) if manager_emails.empty?
    
    mail(
      to: manager_emails,
      subject: "New Rental Booking - #{@rental.name} - #{@customer.full_name}",
      from: branding_from(@business)
    )
  end
end

