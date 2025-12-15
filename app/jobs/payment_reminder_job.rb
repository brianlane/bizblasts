class PaymentReminderJob < ApplicationJob
  queue_as :mailers

  def perform
    # Find all overdue invoices for businesses that have payment reminders enabled
    overdue_invoices = Invoice.joins(:business)
                             .where(status: [:pending, :overdue])
                             .where('due_date < ?', Date.current)
                             .where(businesses: { 
                               payment_reminders_enabled: true 
                             })

    overdue_invoices.find_each do |invoice|
      begin
        # Update invoice status to overdue if it's still pending
        invoice.update!(status: :overdue) if invoice.pending?
        
        # Send reminder (email + SMS)
        NotificationService.invoice_payment_reminder(invoice)
        Rails.logger.info "[NOTIFICATION] Sent payment reminder for Invoice ##{invoice.invoice_number}"
      rescue => e
        Rails.logger.error "[NOTIFICATION] Failed to send payment reminder for Invoice ##{invoice.invoice_number}: #{e.message}"
      end
    end

    Rails.logger.info "[PaymentReminderJob] Processed #{overdue_invoices.count} overdue invoices"
  end
end 