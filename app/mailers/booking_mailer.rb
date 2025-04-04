class BookingMailer < ApplicationMailer
  def confirmation(booking)
    # Placeholder for booking confirmation email
    @booking = booking
    mail(to: booking.email, subject: 'Your booking confirmation')
  end

  def cancellation(booking)
    # Placeholder for booking cancellation email
    @booking = booking
    mail(to: booking.email, subject: 'Your booking has been cancelled')
  end

  def update(booking)
    # Placeholder for booking update email
    @booking = booking
    mail(to: booking.email, subject: 'Your booking has been updated')
  end
end
