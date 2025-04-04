class InvoiceMailer < ApplicationMailer
  def new_invoice(invoice)
    # Placeholder for new invoice email
    @invoice = invoice
    mail(to: invoice.email, subject: 'Your new invoice')
  end

  def payment_reminder(invoice)
    # Placeholder for payment reminder email
    @invoice = invoice
    mail(to: invoice.email, subject: 'Payment reminder for your invoice')
  end

  def payment_confirmation(invoice)
    # Placeholder for payment confirmation email
    @invoice = invoice
    mail(to: invoice.email, subject: 'Payment received for your invoice')
  end
end
