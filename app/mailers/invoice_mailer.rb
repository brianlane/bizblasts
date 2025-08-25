class InvoiceMailer < ApplicationMailer
  # Send invoice with payment link (all tiers)
  def invoice_created(invoice)
    @invoice = invoice
    @business = invoice.business
    @customer = invoice.tenant_customer
    @payment_url = generate_payment_url(invoice)
    
    # Add tier-specific features for premium businesses
    @include_analytics = @business.tier == 'premium'
    
    Rails.logger.info "[EMAIL] InvoiceMailer.invoice_created preparing email for: #{@customer.email} | Invoice: #{@invoice.invoice_number}"
    
    result = mail(
      to: @customer.email,
      subject: "Invoice ##{@invoice.invoice_number} - #{@business.name}",
      reply_to: @business.email
    )
    
    Rails.logger.info "[EMAIL] InvoiceMailer.invoice_created mail object created successfully for: #{@customer.email}"
    result
  rescue => e
    Rails.logger.error "[EMAIL] InvoiceMailer.invoice_created failed for: #{@customer&.email} | Error: #{e.message}"
    raise
  end

  # Send payment confirmation when invoice is paid
  def payment_confirmation(invoice, payment)
    @invoice = invoice
    @business = invoice.business
    @customer = invoice.tenant_customer
    @payment = payment
    
    # Add tier-specific features for premium businesses
    @include_analytics = @business.tier == 'premium'
    
    Rails.logger.info "[EMAIL] InvoiceMailer.payment_confirmation preparing email for: #{@customer.email} | Invoice: #{@invoice.invoice_number}"
    
    mail(
      to: @customer.email,
      subject: "Payment Received - Invoice ##{@invoice.invoice_number} - #{@business.name}",
      reply_to: @business.email
    )
  end

  # Send payment reminder for overdue invoices (standard+ tier only, must be enabled)
  def payment_reminder(invoice)
    return unless invoice.business.tier.in?(['standard', 'premium'])
    return unless invoice.business.payment_reminders_enabled?
    
    @invoice = invoice
    @business = invoice.business
    @customer = invoice.tenant_customer
    @payment_url = generate_payment_url(invoice)
    @days_overdue = (Date.current - invoice.due_date).to_i
    
    # Add tier-specific features for premium businesses
    @include_analytics = @business.tier == 'premium'
    
    mail(
      to: @customer.email,
      subject: "Payment Reminder - Invoice ##{@invoice.invoice_number} - #{@business.name}",
      reply_to: @business.email
    )
  end

  # Send notification when payment fails (standard+ tier only)
  def payment_failed(invoice, payment)
    return unless invoice.business.tier.in?(['standard', 'premium'])
    
    @invoice = invoice
    @business = invoice.business
    @customer = invoice.tenant_customer
    @payment = payment
    @payment_url = generate_payment_url(invoice)
    @failure_reason = payment.failure_reason
    
    # Add tier-specific features for premium businesses
    @include_analytics = @business.tier == 'premium'
    
    mail(
      to: @customer.email,
      subject: "Payment Failed - Invoice ##{@invoice.invoice_number} - #{@business.name}",
      reply_to: @business.email
    )
  end

  private

  def generate_payment_url(invoice)
    # For authenticated users, use transaction path
    # Check if this customer has an associated user account (tenant-scoped)
    user = nil
    if @customer.email.present?
      # Look for user account within business context only
      user = @business.users.find_by(email: @customer.email) ||
             @business.client_businesses.joins(:user).find_by(users: { email: @customer.email })&.user
    end
    
    if user.present?
      Rails.application.routes.url_helpers.tenant_transaction_url(
        invoice, 
        type: 'invoice', 
        subdomain: @business.hostname,
        host: Rails.application.config.action_mailer.default_url_options[:host]
      )
    else
      # For guest users, use guest access token
      Rails.application.routes.url_helpers.tenant_invoice_url(
        invoice,
        token: invoice.guest_access_token,
        subdomain: @business.hostname,
        host: Rails.application.config.action_mailer.default_url_options[:host]
      )
    end
  end
end
