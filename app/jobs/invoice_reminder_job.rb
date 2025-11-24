require 'ostruct'

class InvoiceReminderJob < ApplicationJob
  queue_as :reminders

  def perform(invoice_id, reminder_type = 'upcoming')
    # Find the invoice
    invoice = Invoice.find_by(id: invoice_id)
    return unless invoice
    
    # Skip if invoice is already paid
    return if invoice.paid?
    
    # Determine the reminder type
    case reminder_type
    when 'upcoming'
      # Reminder for invoices due soon
      send_upcoming_reminder(invoice)
    when 'overdue'
      # Reminder for overdue invoices
      send_overdue_reminder(invoice)
    when 'final'
      # Final reminder before collections
      send_final_reminder(invoice)
    end
    
    # Update invoice to record reminder
    invoice.update(
      last_reminder_sent_at: Time.current,
      reminder_count: (invoice.reminder_count || 0) + 1
    )
    
    # Check if invoice is now overdue
    invoice.check_overdue
  end
  
  private
  
  def send_upcoming_reminder(invoice)
    # Send email reminder
    # In a real implementation, this would use ActionMailer
    # InvoiceMailer.upcoming_reminder(invoice).deliver_later
    
    # Log the reminder
    Rails.logger.info "Upcoming invoice reminder sent for invoice ##{invoice.id} at #{Time.current}"
    
    # Optionally send SMS
    send_sms_reminder(invoice, 'Your invoice is due soon')
  end
  
  def send_overdue_reminder(invoice)
    # Send email reminder
    # InvoiceMailer.overdue_reminder(invoice).deliver_later
    
    # Log the reminder
    Rails.logger.info "Overdue invoice reminder sent for invoice ##{invoice.id} at #{Time.current}"
    
    # Send SMS for overdue invoices
    days_overdue = (Date.today - invoice.due_date).to_i
    message = "Your invoice is #{days_overdue} days overdue. Please make payment as soon as possible."
    send_sms_reminder(invoice, message)
  end
  
  def send_final_reminder(invoice)
    # Send email reminder
    # InvoiceMailer.final_reminder(invoice).deliver_later
    
    # Log the reminder
    Rails.logger.info "Final invoice reminder sent for invoice ##{invoice.id} at #{Time.current}"
    
    # Send SMS for final notice
    message = "FINAL NOTICE: Your invoice is overdue. Please make payment to avoid further action."
    send_sms_reminder(invoice, message)
  end
  
  def send_sms_reminder(invoice, message_prefix)
    customer = invoice.customer
    return unless customer&.phone.present?
    
    # Build a more detailed message
    message = "#{message_prefix}. Invoice ##{invoice.id} for $#{invoice.amount} is due on #{invoice.due_date.strftime('%b %d')}. " \
              "Visit #{payment_url(invoice)} to pay online."
    
    # Send the SMS
    SmsService.send_message(
      customer.phone,
      message,
      {
        customer_id: customer.id,
        business_id: invoice.business_id
      }
    )
  end
  
  def payment_url(invoice)
    # This would generate a URL to the payment page using TenantHost helper
    # In a real implementation, this might include a secure token
    mock_request = OpenStruct.new(
      protocol: Rails.env.production? ? 'https://' : 'http://',
      domain: Rails.env.development? || Rails.env.test? ? 'lvh.me' : 'bizblasts.com',
      port: Rails.env.development? ? 3000 : (Rails.env.production? ? 443 : 80)
    )
    TenantHost.url_for(invoice.business, mock_request, "/invoices/#{invoice.id}/pay")
  end
end
