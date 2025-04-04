class ReminderMailer < ApplicationMailer
  def appointment_reminder(appointment)
    # Placeholder for appointment reminder email
    @appointment = appointment
    mail(to: appointment.email, subject: 'Reminder: Your upcoming appointment')
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
