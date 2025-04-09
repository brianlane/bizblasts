class ReminderMailer < ApplicationMailer
  def booking_reminder(booking)
    # Placeholder for booking reminder email
    @booking = booking
    mail(to: booking.email, subject: 'Reminder: Your upcoming booking')
  end

  def follow_up(customer, service)
    # Placeholder for follow-up email
    @customer = customer
    @service = service
    mail(to: customer.email, subject: 'How was your recent service?')
  end

  def document_expiration(customer, document)
    # Placeholder for document expiration reminder
    @customer = customer
    @document = document
    mail(to: customer.email, subject: 'Document expiration reminder')
  end
end
