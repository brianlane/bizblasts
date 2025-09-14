class SmsService
  # This service handles sending SMS messages using Twilio
  
  def self.send_message(phone_number, message, options = {})
    # Early return if SMS is globally disabled
    unless Rails.application.config.sms_enabled
      Rails.logger.info "[SMS_SERVICE] SMS disabled globally, skipping message to #{phone_number}"
      return { success: false, error: "SMS feature disabled" }
    end
    
    # Check business tier restrictions
    business_id = options[:business_id]
    if business_id
      business = Business.find_by(id: business_id)
      if business && !business.can_send_sms?
        Rails.logger.warn "[SMS_SERVICE] Business #{business_id} (tier: #{business.tier}) cannot send SMS - tier restriction"
        return { success: false, error: "Business tier does not support SMS" }
      end
    end
    
    # Check if the phone number is valid
    unless valid_phone_number?(phone_number)
      return { success: false, error: "Invalid phone number format" }
    end
    
    # Create an SMS message record
    sms_message = create_sms_record(phone_number, message, options)
    
    # Send SMS via Twilio API
    begin
      client = Twilio::REST::Client.new(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
      message_resource = client.messages.create(
        messaging_service_sid: TWILIO_MESSAGING_SERVICE_SID,
        to: phone_number,
        body: message
      )
      
      # Twilio returns a message resource with sid. Validate it's present.
      if message_resource.sid.nil? || message_resource.sid.empty?
        raise StandardError, "Twilio did not return a message SID"
      end

      external_id = message_resource.sid
      
      sms_message.update!(
        status: :sent,
        sent_at: Time.current,
        external_id: external_id
      )
      
      Rails.logger.info "SMS sent successfully to #{phone_number} with Twilio SID: #{external_id}"
      { success: true, sms_message: sms_message, external_id: external_id }
      
    rescue Twilio::REST::RestError => e
      error_message = "Twilio API error: #{e.message}"
      sms_message.mark_as_failed!(error_message)
      
      Rails.logger.error "SMS failed to send to #{phone_number}: #{error_message}"
      { success: false, error: error_message, sms_message: sms_message }
      
    rescue => e
      error_message = "Unexpected error: #{e.message}"
      sms_message.mark_as_failed!(error_message)
      
      Rails.logger.error "SMS failed to send to #{phone_number}: #{error_message}"
      { success: false, error: error_message, sms_message: sms_message }
    end
  end

  
  # ===== BOOKING SMS METHODS =====
  def self.send_booking_confirmation(booking)
    variables = build_booking_variables(booking)
    variables[:link] = generate_sms_link(booking.business, "/booking/#{booking.id}/confirmation", booking_id: booking.id)
    
    message = Sms::MessageTemplates.render('booking.confirmation', variables)
    send_message_with_rate_limit(booking.tenant_customer.phone, message, {
      tenant_customer_id: booking.tenant_customer.id,
      booking_id: booking.id,
      business_id: booking.business_id
    })
  end

  def self.send_booking_reminder(booking, timeframe)
    customer = booking.tenant_customer
    service = booking.service
      
    message = "Reminder: Your #{service&.name || 'booking'} is #{timeframe == '24h' ? 'tomorrow' : 'in 1 hour'} at #{booking.local_start_time.strftime('%I:%M %p')}. Reply HELP for assistance or CONFIRM to confirm."
      
    send_message_with_rate_limit(customer.phone, message, { 
      tenant_customer_id: customer.id,
      booking_id: booking.id,
      business_id: booking.business_id
    })
  end

  def self.send_booking_status_update(booking)
    variables = build_booking_variables(booking)
    variables[:link] = generate_sms_link(booking.business, "/booking/#{booking.id}/confirmation", booking_id: booking.id)
    
    message = Sms::MessageTemplates.render('booking.status_update', variables)
    send_message_with_rate_limit(booking.tenant_customer.phone, message, {
      tenant_customer_id: booking.tenant_customer.id,
      booking_id: booking.id,
      business_id: booking.business_id
    })
  end

  def self.send_booking_cancellation(booking)
    variables = build_booking_variables(booking)
    variables[:reason] = booking.cancellation_reason || 'No reason provided'
    variables[:link] = generate_sms_link(booking.business, "/services", booking_id: booking.id)
    
    message = Sms::MessageTemplates.render('booking.cancellation', variables)
    send_message_with_rate_limit(booking.tenant_customer.phone, message, {
      tenant_customer_id: booking.tenant_customer.id,
      booking_id: booking.id,
      business_id: booking.business_id
    })
  end

  def self.send_booking_payment_reminder(booking)
    variables = build_booking_variables(booking)
    variables[:amount] = format_currency(booking.invoice&.amount || booking.total_amount)
    variables[:link] = generate_sms_link(booking.business, "/booking/#{booking.id}/pay", booking_id: booking.id)
    
    message = Sms::MessageTemplates.render('booking.payment_reminder', variables)
    send_message_with_rate_limit(booking.tenant_customer.phone, message, {
      tenant_customer_id: booking.tenant_customer.id,
      booking_id: booking.id,
      business_id: booking.business_id
    })
  end

  def self.send_subscription_booking_created(booking)
    variables = build_booking_variables(booking)
    variables[:link] = generate_sms_link(booking.business, "/booking/#{booking.id}/confirmation", booking_id: booking.id)
    
    message = Sms::MessageTemplates.render('booking.subscription_booking_created', variables)
    send_message_with_rate_limit(booking.tenant_customer.phone, message, {
      tenant_customer_id: booking.tenant_customer.id,
      booking_id: booking.id,
      business_id: booking.business_id
    })
  end

  # ===== INVOICE SMS METHODS =====
  def self.send_invoice_created(invoice)
    variables = build_invoice_variables(invoice)
    variables[:link] = generate_sms_link(invoice.business, "/invoices/#{invoice.id}/pay", invoice_id: invoice.id)
    
    message = Sms::MessageTemplates.render('invoice.created', variables)
    send_message_with_rate_limit(invoice.tenant_customer.phone, message, {
      tenant_customer_id: invoice.tenant_customer.id,
      invoice_id: invoice.id,
      business_id: invoice.business_id
    })
  end

  def self.send_invoice_payment_confirmation(invoice, payment)
    variables = build_invoice_variables(invoice)
    variables[:link] = generate_sms_link(invoice.business, "/invoices/#{invoice.id}", invoice_id: invoice.id)
    
    message = Sms::MessageTemplates.render('invoice.payment_confirmation', variables)
    send_message_with_rate_limit(invoice.tenant_customer.phone, message, {
      tenant_customer_id: invoice.tenant_customer.id,
      invoice_id: invoice.id,
      business_id: invoice.business_id
    })
  end

  def self.send_invoice_payment_reminder(invoice)
    variables = build_invoice_variables(invoice)
    variables[:days_overdue] = (Date.current - invoice.due_date).to_i
    variables[:link] = generate_sms_link(invoice.business, "/invoices/#{invoice.id}/pay", invoice_id: invoice.id)
    
    message = Sms::MessageTemplates.render('invoice.payment_reminder', variables)
    send_message_with_rate_limit(invoice.tenant_customer.phone, message, {
      tenant_customer_id: invoice.tenant_customer.id,
      invoice_id: invoice.id,
      business_id: invoice.business_id
    })
  end

  def self.send_invoice_payment_failed(invoice, payment)
    variables = build_invoice_variables(invoice)
    variables[:link] = generate_sms_link(invoice.business, "/invoices/#{invoice.id}/pay", invoice_id: invoice.id)
    
    message = Sms::MessageTemplates.render('invoice.payment_failed', variables)
    send_message_with_rate_limit(invoice.tenant_customer.phone, message, {
      tenant_customer_id: invoice.tenant_customer.id,
      invoice_id: invoice.id,
      business_id: invoice.business_id
    })
  end

  # ===== ORDER SMS METHODS =====
  def self.send_order_confirmation(order)
    variables = build_order_variables(order)
    variables[:link] = generate_sms_link(order.business, "/orders/#{order.id}", order_id: order.id)
    
    message = Sms::MessageTemplates.render('order.confirmation', variables)
    send_message_with_rate_limit(order.tenant_customer.phone, message, {
      tenant_customer_id: order.tenant_customer.id,
      order_id: order.id,
      business_id: order.business_id
    })
  end

  def self.send_order_status_update(order, previous_status)
    variables = build_order_variables(order)
    variables[:status] = order.status.humanize
    variables[:link] = generate_sms_link(order.business, "/orders/#{order.id}", order_id: order.id)
    
    message = Sms::MessageTemplates.render('order.status_update', variables)
    send_message_with_rate_limit(order.tenant_customer.phone, message, {
      tenant_customer_id: order.tenant_customer.id,
      order_id: order.id,
      business_id: order.business_id
    })
  end

  def self.send_order_refund_confirmation(order, payment)
    variables = build_order_variables(order)
    variables[:amount] = format_currency(payment.refunded_amount || payment.amount)
    
    message = Sms::MessageTemplates.render('order.refund_confirmation', variables)
    send_message_with_rate_limit(order.tenant_customer.phone, message, {
      tenant_customer_id: order.tenant_customer.id,
      order_id: order.id,
      business_id: order.business_id
    })
  end

  def self.send_subscription_order_created(order)
    variables = build_order_variables(order)
    variables[:link] = generate_sms_link(order.business, "/orders/#{order.id}", order_id: order.id)
    
    message = Sms::MessageTemplates.render('order.subscription_order_created', variables)
    send_message_with_rate_limit(order.tenant_customer.phone, message, {
      tenant_customer_id: order.tenant_customer.id,
      order_id: order.id,
      business_id: order.business_id
    })
  end

  # ===== BUSINESS NOTIFICATION SMS METHODS =====
  def self.send_business_new_booking(booking, business_user)
    variables = build_booking_variables(booking)
    variables[:customer_name] = booking.tenant_customer.full_name
    
    message = Sms::MessageTemplates.render('business.new_booking_notification', variables)
    send_message_with_rate_limit(business_user.phone, message, {
      user_id: business_user.id,
      booking_id: booking.id,
      business_id: booking.business_id
    }) if business_user.phone.present?
  end

  def self.send_business_new_order(order, business_user)
    variables = build_order_variables(order)
    variables[:customer_name] = order.tenant_customer.full_name
    
    message = Sms::MessageTemplates.render('business.new_order_notification', variables)
    send_message_with_rate_limit(business_user.phone, message, {
      user_id: business_user.id,
      order_id: order.id,
      business_id: order.business_id
    }) if business_user.phone.present?
  end

  def self.send_business_payment_received(payment, business_user)
    variables = {
      customer_name: payment.tenant_customer.full_name,
      amount: format_currency(payment.amount),
      business_name: payment.business.name,
      item_type: payment.invoice&.booking ? 'booking' : 'order'
    }
    
    message = Sms::MessageTemplates.render('business.payment_received_notification', variables)
    send_message_with_rate_limit(business_user.phone, message, {
      user_id: business_user.id,
      payment_id: payment.id,
      business_id: payment.business_id
    }) if business_user.phone.present?
  end

  # ===== MARKETING SMS METHODS =====
  def self.send_marketing_campaign(campaign, recipient)
    variables = {
      business_name: campaign.business.name,
      offer_text: campaign.content || 'Special offer available',
      link: generate_sms_link(campaign.business, '/', marketing_campaign_id: campaign.id)
    }
    
    message = Sms::MessageTemplates.render('marketing.campaign_promotional', variables)
    send_message_with_rate_limit(recipient.phone, message, {
      tenant_customer_id: recipient.id,
      marketing_campaign_id: campaign.id,
      business_id: campaign.business_id
    })
  end

  def self.send_business_new_customer(customer, business_user)
    variables = {
      customer_name: customer.full_name,
      customer_email: customer.email,
      business_name: customer.business.name
    }
    
    message = Sms::MessageTemplates.render('business.new_customer_notification', variables)
    send_message_with_rate_limit(business_user.phone, message, {
      user_id: business_user.id,
      tenant_customer_id: customer.id,
      business_id: customer.business_id
    }) if business_user.phone.present?
  end

  def self.process_webhook(params)
    # Handle Twilio webhook callbacks for delivery receipts
    # Twilio sends MessageSid in the webhook payload
    
    message_sid = params[:MessageSid] || params['MessageSid']
    status = params[:MessageStatus] || params['MessageStatus']
    
    return { success: false, error: "Missing MessageSid in webhook" } unless message_sid
    return { success: false, error: "Missing MessageStatus in webhook" } unless status
    
    sms_message = SmsMessage.find_by(external_id: message_sid)
    return { success: false, error: "Message not found for SID: #{message_sid}" } unless sms_message
    
    Rails.logger.info "Processing Twilio webhook for message #{message_sid} with status: #{status}"
    
    case status.downcase
    when "delivered"
      sms_message.mark_as_delivered!
      { success: true, sms_message: sms_message, status: "delivered" }
    when "failed", "undelivered"
      error_code = params[:ErrorCode] || params['ErrorCode']
      error_message = "Delivery failed"
      error_message += " (Code: #{error_code})" if error_code
      
      sms_message.mark_as_failed!(error_message)
      { success: false, error: error_message, sms_message: sms_message }
    when "sent", "queued", "accepted"
      # These are intermediate states, don't update our status
      { success: true, status: "acknowledged", sms_message: sms_message }
    else
      Rails.logger.warn "Unknown Twilio status received: #{status}"
      { success: true, status: "unknown", sms_message: sms_message }
    end
  end
  
  private
  
  # Rate-limited version of send_message
  def self.send_message_with_rate_limit(phone, message, options = {})
    business_id = options[:business_id]
    return { success: false, error: "Business ID required for rate limiting" } unless business_id
    
    business = Business.find_by(id: business_id)
    return { success: false, error: "Business not found" } unless business
    
    # Get customer if provided
    customer = nil
    if options[:tenant_customer_id]
      customer = TenantCustomer.find_by(id: options[:tenant_customer_id])
    end
    
    # Check rate limits using centralized rate limiter
    unless SmsRateLimiter.can_send?(business, customer)
      return { success: false, error: "SMS rate limit exceeded" }
    end
    
    # Send the message
    result = send_message(phone, message, options)
    
    # Record the send for rate limiting if successful
    if result[:success]
      SmsRateLimiter.record_send(business, customer)
    end
    
    result
  end

  def self.build_booking_variables(booking)
    {
      service_name: booking.service&.name || 'Booking',
      date: booking.local_start_time.strftime('%m/%d/%Y'),
      time: booking.local_start_time.strftime('%I:%M %p'),
      business_name: booking.business.name,
      address: booking.business.address || booking.business.city
    }
  end

  def self.build_invoice_variables(invoice)
    {
      invoice_number: invoice.invoice_number,
      amount: format_currency(invoice.amount),
      date: invoice.due_date&.strftime('%m/%d/%Y') || 'N/A',
      business_name: invoice.business.name
    }
  end

  def self.build_order_variables(order)
    {
      order_number: order.order_number,
      amount: format_currency(order.total_amount),
      business_name: order.business.name
    }
  end

  def self.format_currency(amount)
    return '0' unless amount
    "$#{'%.2f' % amount}"
  end

  def self.generate_sms_link(business, path, tracking_params = {})
    full_url = TenantHost.url_for(business, nil, path)
    SmsLinkShortener.shorten(full_url, tracking_params)
  end

  def self.valid_phone_number?(phone)
    # Very basic phone validation - this should be enhanced for production
    phone.present? && phone.gsub(/\D/, '').length >= 10
  end
  
  def self.create_sms_record(phone_number, content, options = {})
    # Derive business_id from options or related records
    business_id = options[:business_id] 
    business_id ||= TenantCustomer.find_by(id: options[:tenant_customer_id])&.business_id
    business_id ||= Booking.find_by(id: options[:booking_id])&.business_id
    business_id ||= MarketingCampaign.find_by(id: options[:marketing_campaign_id])&.business_id
    
    unless business_id
      Rails.logger.error "[SMS_SERVICE] Could not determine business_id for SMS message"
      raise ArgumentError, "business_id is required for SMS messages"
    end
    
    SmsMessage.create!(
      phone_number: phone_number,
      content: content,
      status: :pending,
      business_id: business_id,
      tenant_customer_id: options[:tenant_customer_id],
      booking_id: options[:booking_id],
      marketing_campaign_id: options[:marketing_campaign_id]
    )
  end
end
