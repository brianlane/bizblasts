# frozen_string_literal: true

# Service to handle staggered email delivery to avoid rate limits
# Resend has a 2 requests/second limit, so we stagger emails accordingly
class StaggeredEmailService
  # Send multiple emails with staggered timing to respect rate limits
  def self.deliver_multiple(email_jobs, delay_between_emails: 1.second)
    # Filter out nil email jobs (mailers that returned early due to conditions)
    valid_emails = email_jobs.compact
    return if valid_emails.empty?
    
    Rails.logger.info "[StaggeredEmail] Scheduling #{valid_emails.count} emails with #{delay_between_emails} delay"
    
    valid_emails.each_with_index do |email_job, index|
      # First email sends immediately, subsequent emails are delayed
      delay = index * delay_between_emails
      
      if delay == 0
        email_job.deliver_later
        Rails.logger.info "[StaggeredEmail] Email #{index + 1}/#{valid_emails.count} scheduled immediately"
      else
        email_job.deliver_later(wait: delay)
        Rails.logger.info "[StaggeredEmail] Email #{index + 1}/#{valid_emails.count} scheduled with #{delay} delay"
      end
    end
  end
  
  # Helper method for order creation emails (common scenario)
  def self.deliver_order_emails(order)
    begin
      emails = []
      
      # Business notification emails (to manager)
      # Check if customer was just created (within the last 10 seconds)
      customer = order.tenant_customer
      if customer&.persisted? && customer_newly_created?(customer)
        email = BusinessMailer.new_customer_notification(customer)
        emails << email if email.present?
        # Mark customer to skip its own notification callback to avoid duplicates
        customer.skip_notification_email = true
      end
      
      # Business order notification email
      email = BusinessMailer.new_order_notification(order)
      emails << email if email.present?
      
      # Customer invoice email (if invoice exists)
      if order.invoice&.persisted?
        email = InvoiceMailer.invoice_created(order.invoice)
        emails << email if email.present?
      end
      
      # Send emails with 1-second stagger (respects 2/second rate limit with buffer)
      deliver_multiple(emails, delay_between_emails: 1.second)
      
      Rails.logger.info "[EMAIL] Scheduled staggered emails for Order ##{order.order_number}"
    rescue => e
      Rails.logger.error "[EMAIL] Failed to schedule staggered emails for Order ##{order.order_number}: #{e.message}"
      # Don't re-raise the error to prevent disrupting order creation
    end
  end
  
  # Helper method for booking creation emails
  def self.deliver_booking_emails(booking)
    begin
      emails = []
      
      # Business notification emails
      customer = booking.tenant_customer
      if customer&.persisted? && customer_newly_created?(customer)
        email = BusinessMailer.new_customer_notification(customer)
        emails << email if email.present?
        # Mark customer to skip its own notification callback to avoid duplicates
        customer.skip_notification_email = true
      end
      
      # Business booking notification email
      email = BusinessMailer.new_booking_notification(booking)
      emails << email if email.present?
      
      # Customer invoice email (if invoice exists)
      if booking.invoice&.persisted?
        email = InvoiceMailer.invoice_created(booking.invoice)
        emails << email if email.present?
      end
      
      # Send emails with stagger
      deliver_multiple(emails, delay_between_emails: 1.second)
      
      Rails.logger.info "[EMAIL] Scheduled staggered emails for Booking ##{booking.id}"
    rescue => e
      Rails.logger.error "[EMAIL] Failed to schedule staggered emails for Booking ##{booking.id}: #{e.message}"
      # Don't re-raise the error to prevent disrupting booking creation
    end
  end
  
  private
  
  # Check if this customer was just created in this request
  def self.customer_newly_created?(customer)
    return false unless customer&.persisted?
    
    # Customer was created within the last 10 seconds (recent creation)
    customer.created_at > 10.seconds.ago
  end
end 