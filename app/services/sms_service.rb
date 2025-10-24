class SmsService
  # This service handles sending SMS messages using Twilio

  
  def self.send_message(phone_number, message, options = {})
    # Early return if SMS is globally disabled
    unless Rails.application.config.sms_enabled
      SecureLogger.info "[SMS_SERVICE] SMS disabled globally, skipping message to #{phone_number}"
      return { success: false, error: "SMS feature disabled" }
    end
    
    # Check business tier restrictions
    business_id = options[:business_id]
    if business_id
      business = Business.find_by(id: business_id)
      if business && !business.can_send_sms?
        SecureLogger.warn "[SMS_SERVICE] Business #{business_id} (tier: #{business.tier}) cannot send SMS - tier restriction"
        return { success: false, error: "Business tier does not support SMS" }
      end
    end
    
    # Check if the phone number is valid
    unless valid_phone_number?(phone_number)
      return { success: false, error: "Invalid phone number format" }
    end
    
    normalized_phone = PhoneNormalizer.normalize(phone_number)
    return { success: false, error: "Invalid phone number format" } if normalized_phone.blank?
    sms_message = create_sms_record(normalized_phone, message, options)
    
    # Send SMS via Twilio API with enhanced error monitoring
    start_time = Time.current
    begin
      SecureLogger.debug "[SMS_SERVICE] Initiating Twilio API call to send SMS to #{normalized_phone}"

      client = Twilio::REST::Client.new(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
      message_resource = client.messages.create(
        messaging_service_sid: TWILIO_MESSAGING_SERVICE_SID,
        to: normalized_phone,
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

      duration = Time.current - start_time
      SecureLogger.info "[SMS_SERVICE] SMS sent successfully to #{normalized_phone} with Twilio SID: #{external_id} (#{duration.round(3)}s)"
      { success: true, sms_message: sms_message, external_id: external_id }

    rescue Twilio::REST::RestError => e
      duration = Time.current - start_time
      error_message = "Twilio API error: #{e.message}"

      # Enhanced logging for IP transition monitoring
      if e.code == 20003 # Authentication Error
        SecureLogger.error "[SMS_SERVICE] TWILIO AUTHENTICATION ERROR after #{duration.round(3)}s: #{e.message}"
        SecureLogger.error "[SMS_SERVICE] This may indicate IP allowlist issues after Render IP change"
      elsif e.code.to_s.start_with?('2') # 2xxxx codes are typically auth/permission related
        SecureLogger.error "[SMS_SERVICE] TWILIO PERMISSION ERROR (code #{e.code}) after #{duration.round(3)}s: #{e.message}"
        SecureLogger.error "[SMS_SERVICE] This may indicate IP allowlist issues after Render IP change"
      else
        SecureLogger.error "[SMS_SERVICE] TWILIO ERROR (code #{e.code}) after #{duration.round(3)}s: #{e.message}"
      end

      sms_message.mark_as_failed!(error_message)
      { success: false, error: error_message, sms_message: sms_message }

    rescue Net::OpenTimeout, Net::ReadTimeout => e
      duration = Time.current - start_time
      error_message = "Network timeout: #{e.message}"
      SecureLogger.error "[SMS_SERVICE] NETWORK TIMEOUT after #{duration.round(3)}s: #{e.message}"
      SecureLogger.error "[SMS_SERVICE] This may indicate network connectivity issues"
      sms_message.mark_as_failed!(error_message)
      { success: false, error: error_message, sms_message: sms_message }

    rescue => e
      duration = Time.current - start_time
      error_message = "Unexpected error: #{e.message}"
      SecureLogger.error "[SMS_SERVICE] UNEXPECTED ERROR after #{duration.round(3)}s: #{e.class.name} - #{e.message}"
      sms_message.mark_as_failed!(error_message)
      { success: false, error: error_message, sms_message: sms_message }
    end
  end

  
  # ===== BOOKING SMS METHODS =====
  def self.send_booking_confirmation(booking)
    # Check TCPA compliance - customer must be opted in
    unless booking.tenant_customer.can_receive_sms?(:booking)
      SecureLogger.info "[SMS_SERVICE] Customer #{booking.tenant_customer.id} not opted in for booking SMS"

      # Try to send opt-in invitation if appropriate
      if should_send_invitation?(booking.tenant_customer, booking.business, :booking_confirmation)
        send_opt_in_invitation(booking.tenant_customer, booking.business, :booking_confirmation)
      end

      # Queue the notification for later delivery instead of failing
      variables = build_booking_variables(booking)
      variables[:link] = generate_sms_link(booking.business, "/booking/#{booking.id}/confirmation", booking_id: booking.id)

      queued_notification = PendingSmsNotification.queue_booking_notification(
        'booking_confirmation',
        booking,
        variables
      )

      SecureLogger.info "[SMS_SERVICE] Queued booking confirmation for customer #{booking.tenant_customer.id} (notification #{queued_notification.id})"
      return { success: false, error: "Customer not opted in for SMS notifications", queued: true, notification_id: queued_notification.id }
    end

    variables = build_booking_variables(booking)
    variables[:link] = generate_sms_link(booking.business, "/booking/#{booking.id}/confirmation", booking_id: booking.id)

    message = Sms::MessageTemplates.render('booking.confirmation', variables)
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render booking confirmation template"
      return { success: false, error: "Failed to render SMS template" }
    end

    send_message_with_rate_limit(booking.tenant_customer.phone, message, {
      tenant_customer_id: booking.tenant_customer.id,
      booking_id: booking.id,
      business_id: booking.business_id
    })
  end

  def self.send_booking_reminder(booking, timeframe)
    customer = booking.tenant_customer

    # Prepare variables for template rendering (used by both paths)
    variables = build_booking_variables(booking)
    variables[:timeframe_text] = timeframe == '24h' ? 'tomorrow' : 'in 1 hour'

    # Check TCPA compliance - customer must be opted in
    unless customer.can_receive_sms?(:reminder)
      SecureLogger.info "[SMS_SERVICE] Customer #{customer.id} not opted in for reminder SMS"

      # Try to send opt-in invitation if appropriate
      if should_send_invitation?(customer, booking.business, :booking_reminder)
        send_opt_in_invitation(customer, booking.business, :booking_reminder)
      end

      # Queue the notification for later delivery instead of failing
      queued_notification = PendingSmsNotification.queue_booking_notification(
        'booking_reminder',
        booking,
        variables.merge(timeframe: timeframe)
      )

      SecureLogger.info "[SMS_SERVICE] Queued booking reminder for customer #{customer.id} (notification #{queued_notification.id})"
      return { success: false, error: "Customer not opted in for SMS notifications", queued: true, notification_id: queued_notification.id }
    end

    # Use template rendering for immediate send (consistent with queued path)
    message = Sms::MessageTemplates.render('booking.reminder', variables)
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render booking reminder template"
      return { success: false, error: "Failed to render SMS template" }
    end

    send_message_with_rate_limit(customer.phone, message, {
      tenant_customer_id: customer.id,
      booking_id: booking.id,
      business_id: booking.business_id
    })
  end

  def self.send_booking_status_update(booking)
    # Check TCPA compliance - customer must be opted in
    unless booking.tenant_customer.can_receive_sms?(:booking)
      SecureLogger.info "[SMS_SERVICE] Customer #{booking.tenant_customer.id} not opted in for booking status SMS"

      # Queue the notification for later delivery instead of failing
      variables = build_booking_variables(booking)
      variables[:link] = generate_sms_link(booking.business, "/booking/#{booking.id}/confirmation", booking_id: booking.id)

      queued_notification = PendingSmsNotification.queue_booking_notification(
        'booking_status_update',
        booking,
        variables
      )

      SecureLogger.info "[SMS_SERVICE] Queued booking status update for customer #{booking.tenant_customer.id} (notification #{queued_notification.id})"
      return { success: false, error: "Customer not opted in for SMS notifications", queued: true, notification_id: queued_notification.id }
    end

    variables = build_booking_variables(booking)
    variables[:link] = generate_sms_link(booking.business, "/booking/#{booking.id}/confirmation", booking_id: booking.id)

    message = Sms::MessageTemplates.render('booking.status_update', variables)
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render booking status update template"
      return { success: false, error: "Failed to render SMS template" }
    end

    send_message_with_rate_limit(booking.tenant_customer.phone, message, {
      tenant_customer_id: booking.tenant_customer.id,
      booking_id: booking.id,
      business_id: booking.business_id
    })
  end

  def self.send_booking_cancellation(booking)
    # Check TCPA compliance - customer must be opted in
    unless booking.tenant_customer.can_receive_sms?(:booking)
      SecureLogger.info "[SMS_SERVICE] Customer #{booking.tenant_customer.id} not opted in for cancellation SMS"

      # Try to send opt-in invitation if appropriate
      if should_send_invitation?(booking.tenant_customer, booking.business, :booking_cancellation)
        send_opt_in_invitation(booking.tenant_customer, booking.business, :booking_cancellation)
      end

      # Queue the notification for later delivery instead of failing
      variables = build_booking_variables(booking)
      variables[:reason] = booking.cancellation_reason || 'No reason provided'
      variables[:link] = generate_sms_link(booking.business, "/services", booking_id: booking.id)

      queued_notification = PendingSmsNotification.queue_booking_notification(
        'booking_cancellation',
        booking,
        variables
      )

      SecureLogger.info "[SMS_SERVICE] Queued booking cancellation for customer #{booking.tenant_customer.id} (notification #{queued_notification.id})"
      return { success: false, error: "Customer not opted in for SMS notifications", queued: true, notification_id: queued_notification.id }
    end
    
    variables = build_booking_variables(booking)
    variables[:reason] = booking.cancellation_reason || 'No reason provided'
    variables[:link] = generate_sms_link(booking.business, "/services", booking_id: booking.id)
    
    message = Sms::MessageTemplates.render('booking.cancellation', variables)
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render booking cancellation template"
      return { success: false, error: "Failed to render SMS template" }
    end

    send_message_with_rate_limit(booking.tenant_customer.phone, message, {
      tenant_customer_id: booking.tenant_customer.id,
      booking_id: booking.id,
      business_id: booking.business_id
    })
  end

  def self.send_booking_payment_reminder(booking)
    # Check TCPA compliance - customer must be opted in
    unless booking.tenant_customer.can_receive_sms?(:payment)
      SecureLogger.info "[SMS_SERVICE] Customer #{booking.tenant_customer.id} not opted in for payment reminder SMS"

      # Try to send opt-in invitation if appropriate
      if should_send_invitation?(booking.tenant_customer, booking.business, :booking_payment_reminder)
        send_opt_in_invitation(booking.tenant_customer, booking.business, :booking_payment_reminder)
      end

      # Queue the notification for later delivery instead of failing
      variables = build_booking_variables(booking)
      variables[:amount] = format_currency(booking.invoice&.amount || booking.total_amount)
      variables[:link] = generate_sms_link(booking.business, "/booking/#{booking.id}/pay", booking_id: booking.id)

      queued_notification = PendingSmsNotification.queue_booking_notification(
        'booking_payment_reminder',
        booking,
        variables
      )

      SecureLogger.info "[SMS_SERVICE] Queued booking payment reminder for customer #{booking.tenant_customer.id} (notification #{queued_notification.id})"
      return { success: false, error: "Customer not opted in for SMS notifications", queued: true, notification_id: queued_notification.id }
    end
    
    variables = build_booking_variables(booking)
    variables[:amount] = format_currency(booking.invoice&.amount || booking.total_amount)
    variables[:link] = generate_sms_link(booking.business, "/booking/#{booking.id}/pay", booking_id: booking.id)
    
    message = Sms::MessageTemplates.render('booking.payment_reminder', variables)
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render booking payment reminder template"
      return { success: false, error: "Failed to render SMS template" }
    end

    send_message_with_rate_limit(booking.tenant_customer.phone, message, {
      tenant_customer_id: booking.tenant_customer.id,
      booking_id: booking.id,
      business_id: booking.business_id
    })
  end

  def self.send_subscription_booking_created(booking)
    # Check TCPA compliance - customer must be opted in
    unless booking.tenant_customer.can_receive_sms?(:subscription)
      SecureLogger.info "[SMS_SERVICE] Customer #{booking.tenant_customer.id} not opted in for subscription SMS"

      # Try to send opt-in invitation if appropriate
      if should_send_invitation?(booking.tenant_customer, booking.business, :subscription_booking_created)
        send_opt_in_invitation(booking.tenant_customer, booking.business, :subscription_booking_created)
      end

      # Queue the notification for later delivery instead of failing
      variables = build_booking_variables(booking)
      variables[:link] = generate_sms_link(booking.business, "/booking/#{booking.id}/confirmation", booking_id: booking.id)

      queued_notification = PendingSmsNotification.queue_booking_notification(
        'subscription_booking_created',
        booking,
        variables
      )

      SecureLogger.info "[SMS_SERVICE] Queued subscription booking created for customer #{booking.tenant_customer.id} (notification #{queued_notification.id})"
      return { success: false, error: "Customer not opted in for SMS notifications", queued: true, notification_id: queued_notification.id }
    end
    
    variables = build_booking_variables(booking)
    variables[:link] = generate_sms_link(booking.business, "/booking/#{booking.id}/confirmation", booking_id: booking.id)
    
    message = Sms::MessageTemplates.render('booking.subscription_booking_created', variables)
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render subscription booking created template"
      return { success: false, error: "Failed to render SMS template" }
    end

    send_message_with_rate_limit(booking.tenant_customer.phone, message, {
      tenant_customer_id: booking.tenant_customer.id,
      booking_id: booking.id,
      business_id: booking.business_id
    })
  end

  # ===== INVOICE SMS METHODS =====
  def self.send_invoice_created(invoice)
    # Check TCPA compliance - customer must be opted in
    unless invoice.tenant_customer.can_receive_sms?(:order)
      SecureLogger.info "[SMS_SERVICE] Customer #{invoice.tenant_customer.id} not opted in for invoice SMS"

      # Queue the notification for later delivery instead of failing
      variables = build_invoice_variables(invoice)
      variables[:link] = generate_sms_link(invoice.business, "/invoices/#{invoice.id}/pay", invoice_id: invoice.id)

      queued_notification = PendingSmsNotification.queue_invoice_notification(
        'invoice_created',
        invoice,
        variables
      )

      SecureLogger.info "[SMS_SERVICE] Queued invoice created notification for customer #{invoice.tenant_customer.id} (notification #{queued_notification.id})"
      return { success: false, error: "Customer not opted in for SMS notifications", queued: true, notification_id: queued_notification.id }
    end

    variables = build_invoice_variables(invoice)
    variables[:link] = generate_sms_link(invoice.business, "/invoices/#{invoice.id}/pay", invoice_id: invoice.id)

    message = Sms::MessageTemplates.render('invoice.created', variables)
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render invoice created template"
      return { success: false, error: "Failed to render SMS template" }
    end

    send_message_with_rate_limit(invoice.tenant_customer.phone, message, {
      tenant_customer_id: invoice.tenant_customer.id,
      invoice_id: invoice.id,
      business_id: invoice.business_id
    })
  end

  def self.send_invoice_payment_confirmation(invoice, payment)
    # Check TCPA compliance - customer must be opted in
    unless invoice.tenant_customer.can_receive_sms?(:payment)
      SecureLogger.info "[SMS_SERVICE] Customer #{invoice.tenant_customer.id} not opted in for payment confirmation SMS"

      # Try to send opt-in invitation if appropriate
      if should_send_invitation?(invoice.tenant_customer, invoice.business, :invoice_payment_confirmation)
        send_opt_in_invitation(invoice.tenant_customer, invoice.business, :invoice_payment_confirmation)
      end

      # Queue the notification for later delivery instead of failing
      variables = build_invoice_variables(invoice)
      variables[:link] = generate_sms_link(invoice.business, "/invoices/#{invoice.id}", invoice_id: invoice.id)
      variables[:payment_id] = payment.id if payment

      queued_notification = PendingSmsNotification.queue_invoice_notification(
        'invoice_payment_confirmation',
        invoice,
        variables
      )

      SecureLogger.info "[SMS_SERVICE] Queued invoice payment confirmation for customer #{invoice.tenant_customer.id} (notification #{queued_notification.id})"
      return { success: false, error: "Customer not opted in for SMS notifications", queued: true, notification_id: queued_notification.id }
    end
    
    variables = build_invoice_variables(invoice)
    variables[:link] = generate_sms_link(invoice.business, "/invoices/#{invoice.id}", invoice_id: invoice.id)
    
    message = Sms::MessageTemplates.render('invoice.payment_confirmation', variables)
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render invoice payment confirmation template"
      return { success: false, error: "Failed to render SMS template" }
    end

    send_message_with_rate_limit(invoice.tenant_customer.phone, message, {
      tenant_customer_id: invoice.tenant_customer.id,
      invoice_id: invoice.id,
      business_id: invoice.business_id
    })
  end

  def self.send_invoice_payment_reminder(invoice)
    # Check TCPA compliance - customer must be opted in
    unless invoice.tenant_customer.can_receive_sms?(:payment)
      SecureLogger.info "[SMS_SERVICE] Customer #{invoice.tenant_customer.id} not opted in for payment reminder SMS"

      # Try to send opt-in invitation if appropriate
      if should_send_invitation?(invoice.tenant_customer, invoice.business, :invoice_payment_reminder)
        send_opt_in_invitation(invoice.tenant_customer, invoice.business, :invoice_payment_reminder)
      end

      # Queue the notification for later delivery instead of failing
      variables = build_invoice_variables(invoice)
      variables[:days_overdue] = (Date.current - invoice.due_date).to_i
      variables[:link] = generate_sms_link(invoice.business, "/invoices/#{invoice.id}/pay", invoice_id: invoice.id)

      queued_notification = PendingSmsNotification.queue_invoice_notification(
        'invoice_payment_reminder',
        invoice,
        variables
      )

      SecureLogger.info "[SMS_SERVICE] Queued invoice payment reminder for customer #{invoice.tenant_customer.id} (notification #{queued_notification.id})"
      return { success: false, error: "Customer not opted in for SMS notifications", queued: true, notification_id: queued_notification.id }
    end
    
    variables = build_invoice_variables(invoice)
    variables[:days_overdue] = (Date.current - invoice.due_date).to_i
    variables[:link] = generate_sms_link(invoice.business, "/invoices/#{invoice.id}/pay", invoice_id: invoice.id)
    
    message = Sms::MessageTemplates.render('invoice.payment_reminder', variables)
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render invoice payment reminder template"
      return { success: false, error: "Failed to render SMS template" }
    end

    send_message_with_rate_limit(invoice.tenant_customer.phone, message, {
      tenant_customer_id: invoice.tenant_customer.id,
      invoice_id: invoice.id,
      business_id: invoice.business_id
    })
  end

  def self.send_invoice_payment_failed(invoice, payment)
    # Check TCPA compliance - customer must be opted in
    unless invoice.tenant_customer.can_receive_sms?(:payment)
      SecureLogger.info "[SMS_SERVICE] Customer #{invoice.tenant_customer.id} not opted in for payment failed SMS"

      # Try to send opt-in invitation if appropriate
      if should_send_invitation?(invoice.tenant_customer, invoice.business, :invoice_payment_failed)
        send_opt_in_invitation(invoice.tenant_customer, invoice.business, :invoice_payment_failed)
      end

      # Queue the notification for later delivery instead of failing
      variables = build_invoice_variables(invoice)
      variables[:link] = generate_sms_link(invoice.business, "/invoices/#{invoice.id}/pay", invoice_id: invoice.id)
      variables[:payment_id] = payment.id if payment

      queued_notification = PendingSmsNotification.queue_invoice_notification(
        'invoice_payment_failed',
        invoice,
        variables
      )

      SecureLogger.info "[SMS_SERVICE] Queued invoice payment failed for customer #{invoice.tenant_customer.id} (notification #{queued_notification.id})"
      return { success: false, error: "Customer not opted in for SMS notifications", queued: true, notification_id: queued_notification.id }
    end
    
    variables = build_invoice_variables(invoice)
    variables[:link] = generate_sms_link(invoice.business, "/invoices/#{invoice.id}/pay", invoice_id: invoice.id)
    
    message = Sms::MessageTemplates.render('invoice.payment_failed', variables)
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render invoice payment failed template"
      return { success: false, error: "Failed to render SMS template" }
    end

    send_message_with_rate_limit(invoice.tenant_customer.phone, message, {
      tenant_customer_id: invoice.tenant_customer.id,
      invoice_id: invoice.id,
      business_id: invoice.business_id
    })
  end

  # ===== ORDER SMS METHODS =====
  def self.send_order_confirmation(order)
    # Check TCPA compliance - customer must be opted in
    unless order.tenant_customer.can_receive_sms?(:order)
      SecureLogger.info "[SMS_SERVICE] Customer #{order.tenant_customer.id} not opted in for order confirmation SMS"

      # Try to send opt-in invitation if appropriate
      if should_send_invitation?(order.tenant_customer, order.business, :order_confirmation)
        send_opt_in_invitation(order.tenant_customer, order.business, :order_confirmation)
      end

      # Queue the notification for later delivery instead of failing
      variables = build_order_variables(order)
      variables[:link] = generate_sms_link(order.business, "/orders/#{order.id}", order_id: order.id)

      queued_notification = PendingSmsNotification.queue_order_notification(
        'order_confirmation',
        order,
        variables
      )

      SecureLogger.info "[SMS_SERVICE] Queued order confirmation for customer #{order.tenant_customer.id} (notification #{queued_notification.id})"
      return { success: false, error: "Customer not opted in for SMS notifications", queued: true, notification_id: queued_notification.id }
    end
    
    variables = build_order_variables(order)
    variables[:link] = generate_sms_link(order.business, "/orders/#{order.id}", order_id: order.id)
    
    message = Sms::MessageTemplates.render('order.confirmation', variables)
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render order confirmation template"
      return { success: false, error: "Failed to render SMS template" }
    end

    send_message_with_rate_limit(order.tenant_customer.phone, message, {
      tenant_customer_id: order.tenant_customer.id,
      order_id: order.id,
      business_id: order.business_id
    })
  end

  def self.send_order_status_update(order, previous_status)
    # Check TCPA compliance - customer must be opted in
    unless order.tenant_customer.can_receive_sms?(:order)
      SecureLogger.info "[SMS_SERVICE] Customer #{order.tenant_customer.id} not opted in for order status SMS"

      # Try to send opt-in invitation if appropriate
      if should_send_invitation?(order.tenant_customer, order.business, :order_status_update)
        send_opt_in_invitation(order.tenant_customer, order.business, :order_status_update)
      end

      # Queue the notification for later delivery instead of failing
      variables = build_order_variables(order)
      variables[:status] = order.status.humanize
      variables[:link] = generate_sms_link(order.business, "/orders/#{order.id}", order_id: order.id)
      variables[:previous_status] = previous_status

      queued_notification = PendingSmsNotification.queue_order_notification(
        'order_status_update',
        order,
        variables
      )

      SecureLogger.info "[SMS_SERVICE] Queued order status update for customer #{order.tenant_customer.id} (notification #{queued_notification.id})"
      return { success: false, error: "Customer not opted in for SMS notifications", queued: true, notification_id: queued_notification.id }
    end
    
    variables = build_order_variables(order)
    variables[:status] = order.status.humanize
    variables[:link] = generate_sms_link(order.business, "/orders/#{order.id}", order_id: order.id)
    
    message = Sms::MessageTemplates.render('order.status_update', variables)
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render order status update template"
      return { success: false, error: "Failed to render SMS template" }
    end

    send_message_with_rate_limit(order.tenant_customer.phone, message, {
      tenant_customer_id: order.tenant_customer.id,
      order_id: order.id,
      business_id: order.business_id
    })
  end

  def self.send_order_refund_confirmation(order, payment)
    # Check TCPA compliance - customer must be opted in
    unless order.tenant_customer.can_receive_sms?(:order)
      SecureLogger.info "[SMS_SERVICE] Customer #{order.tenant_customer.id} not opted in for refund confirmation SMS"

      # Try to send opt-in invitation if appropriate
      if should_send_invitation?(order.tenant_customer, order.business, :order_refund_confirmation)
        send_opt_in_invitation(order.tenant_customer, order.business, :order_refund_confirmation)
      end

      # Queue the notification for later delivery instead of failing
      variables = build_order_variables(order)
      variables[:amount] = format_currency(payment.refunded_amount || payment.amount)
      variables[:payment_id] = payment.id if payment

      queued_notification = PendingSmsNotification.queue_order_notification(
        'order_refund_confirmation',
        order,
        variables
      )

      SecureLogger.info "[SMS_SERVICE] Queued order refund confirmation for customer #{order.tenant_customer.id} (notification #{queued_notification.id})"
      return { success: false, error: "Customer not opted in for SMS notifications", queued: true, notification_id: queued_notification.id }
    end
    
    variables = build_order_variables(order)
    variables[:amount] = format_currency(payment.refunded_amount || payment.amount)
    
    message = Sms::MessageTemplates.render('order.refund_confirmation', variables)
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render order refund confirmation template"
      return { success: false, error: "Failed to render SMS template" }
    end

    send_message_with_rate_limit(order.tenant_customer.phone, message, {
      tenant_customer_id: order.tenant_customer.id,
      order_id: order.id,
      business_id: order.business_id
    })
  end

  def self.send_subscription_order_created(order)
    # Check TCPA compliance - customer must be opted in
    unless order.tenant_customer.can_receive_sms?(:subscription)
      SecureLogger.info "[SMS_SERVICE] Customer #{order.tenant_customer.id} not opted in for subscription order SMS"

      # Try to send opt-in invitation if appropriate
      if should_send_invitation?(order.tenant_customer, order.business, :subscription_order_created)
        send_opt_in_invitation(order.tenant_customer, order.business, :subscription_order_created)
      end

      # Queue the notification for later delivery instead of failing
      variables = build_order_variables(order)
      variables[:link] = generate_sms_link(order.business, "/orders/#{order.id}", order_id: order.id)

      queued_notification = PendingSmsNotification.queue_order_notification(
        'subscription_order_created',
        order,
        variables
      )

      SecureLogger.info "[SMS_SERVICE] Queued subscription order created for customer #{order.tenant_customer.id} (notification #{queued_notification.id})"
      return { success: false, error: "Customer not opted in for SMS notifications", queued: true, notification_id: queued_notification.id }
    end
    
    variables = build_order_variables(order)
    variables[:link] = generate_sms_link(order.business, "/orders/#{order.id}", order_id: order.id)
    
    message = Sms::MessageTemplates.render('order.subscription_order_created', variables)
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render subscription order created template"
      return { success: false, error: "Failed to render SMS template" }
    end

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
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render business new booking notification template"
      return { success: false, error: "Failed to render SMS template" }
    end

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
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render business new order notification template"
      return { success: false, error: "Failed to render SMS template" }
    end

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
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render business payment received notification template"
      return { success: false, error: "Failed to render SMS template" }
    end

    send_message_with_rate_limit(business_user.phone, message, {
      user_id: business_user.id,
      payment_id: payment.id,
      business_id: payment.business_id
    }) if business_user.phone.present?
  end

  # ===== MARKETING SMS METHODS =====
  def self.send_marketing_campaign(campaign, recipient)
    # Check TCPA compliance - customer must be opted in for marketing SMS
    unless recipient.can_receive_sms?(:marketing)
      SecureLogger.info "[SMS_SERVICE] Customer #{recipient.id} not opted in for marketing SMS"

      # Try to send opt-in invitation if appropriate
      if should_send_invitation?(recipient, campaign.business, :marketing_campaign)
        send_opt_in_invitation(recipient, campaign.business, :marketing_campaign)
      end

      # Queue the notification for later delivery instead of failing
      variables = {
        business_name: campaign.business.name,
        offer_text: campaign.content || 'Special offer available',
        link: generate_sms_link(campaign.business, '/', marketing_campaign_id: campaign.id)
      }

      queued_notification = PendingSmsNotification.queue_notification(
        notification_type: 'marketing_campaign',
        customer: recipient,
        business: campaign.business,
        sms_type: 'marketing',
        template_data: variables
      )

      SecureLogger.info "[SMS_SERVICE] Queued marketing campaign for customer #{recipient.id} (notification #{queued_notification.id})"
      return { success: false, error: "Customer not opted in for SMS notifications", queued: true, notification_id: queued_notification.id }
    end
    
    variables = {
      business_name: campaign.business.name,
      offer_text: campaign.content || 'Special offer available',
      link: generate_sms_link(campaign.business, '/', marketing_campaign_id: campaign.id)
    }
    
    message = Sms::MessageTemplates.render('marketing.campaign_promotional', variables)
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render marketing campaign promotional template"
      return { success: false, error: "Failed to render SMS template" }
    end

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
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render business new customer notification template"
      return { success: false, error: "Failed to render SMS template" }
    end

    send_message_with_rate_limit(business_user.phone, message, {
      user_id: business_user.id,
      tenant_customer_id: customer.id,
      business_id: customer.business_id
    }) if business_user.phone.present?
  end

  # Send review request SMS to customer
  def self.send_review_request(customer, business, service_name, review_url)
    return unless customer.phone.present?

    # Build variables for template
    variables = {
      service_name: service_name,
      link: review_url,
      business_name: business.name
    }

    # Render the message using existing template system
    message = Sms::MessageTemplates.render('review_request.google_review_request', variables)
    unless message
      SecureLogger.error "[SMS_SERVICE] Failed to render review request template"
      return { success: false, error: "Failed to render SMS template" }
    end

    # Use the customer's business_id if the provided business is not persisted
    business_id = if business&.persisted?
      business.id
    else
      customer.business_id
    end

    send_message_with_rate_limit(
      customer.phone,
      message,
      {
        business_id: business_id,
        tenant_customer_id: customer.id,
        message_type: 'review_request'
      }
    )
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
    
    SecureLogger.info "Processing Twilio webhook for message #{message_sid} with status: #{status}"
    
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
      SecureLogger.warn "Unknown Twilio status received: #{status}"
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
  
  def self.create_sms_record(normalized_phone_number, content, options = {})
    # Derive business_id from options or related records
    business_id = options[:business_id] 
    business_id ||= TenantCustomer.find_by(id: options[:tenant_customer_id])&.business_id
    business_id ||= Booking.find_by(id: options[:booking_id])&.business_id
    business_id ||= MarketingCampaign.find_by(id: options[:marketing_campaign_id])&.business_id
    
    unless business_id
      SecureLogger.error "[SMS_SERVICE] Could not determine business_id for SMS message"
      raise ArgumentError, "business_id is required for SMS messages"
    end
    
    # Security Note: Phone number is automatically encrypted via ActiveRecord::Encryption
    # The SmsMessage model declares: encrypts :phone_number, deterministic: true
    # This ensures the phone_number is encrypted before storage in phone_number_ciphertext column
    SmsMessage.create!(
      phone_number: normalized_phone_number, # Encrypted automatically by model
      content: content,
      status: :pending,
      business_id: business_id,
      tenant_customer_id: options[:tenant_customer_id],
      booking_id: options[:booking_id],
      marketing_campaign_id: options[:marketing_campaign_id]
    )
  end

  # ===== SMS OPT-IN INVITATION METHODS =====

  # Check if we should send an opt-in invitation to the customer
  def self.should_send_invitation?(customer, business, context)
    # Global feature flag check
    unless Rails.application.config.sms_enabled
      SecureLogger.debug "[SMS_INVITATION] SMS disabled globally, not sending invitation"
      return false
    end

    # Business feature flag check
    unless business.sms_auto_invitations_enabled?
      SecureLogger.debug "[SMS_INVITATION] Auto-invitations disabled for business #{business&.safe_identifier_for_logging}"
      return false
    end

    # Customer must have a phone number
    unless customer.phone.present?
      SecureLogger.debug "[SMS_INVITATION] Customer #{customer.id} has no phone number"
      return false
    end

    # Business must be able to send SMS
    unless business.can_send_sms?
      SecureLogger.debug "[SMS_INVITATION] Business #{business&.safe_identifier_for_logging} cannot send SMS"
      return false
    end

    # Customer must not already be opted in
    if customer.phone_opt_in?
      SecureLogger.debug "[SMS_INVITATION] Customer #{customer.id} already opted in"
      return false
    end

    # Customer must not be opted out from this business
    if customer.opted_out_from_business?(business)
      SecureLogger.debug "[SMS_INVITATION] Customer #{customer.id} opted out from business #{business&.safe_identifier_for_logging}"
      return false
    end

    # Must not have sent invitation recently (30-day rule)
    unless customer.can_receive_invitation_from?(business)
      SecureLogger.debug "[SMS_INVITATION] Recent invitation already sent to customer #{customer.id} for business #{business&.safe_identifier_for_logging}"
      return false
    end

    # Never invite for marketing SMS (compliance)
    if context == :marketing
      SecureLogger.debug "[SMS_INVITATION] Not sending invitation for marketing context"
      return false
    end

    true
  end

  # Send an opt-in invitation to the customer
  def self.send_opt_in_invitation(customer, business, context)
    SecureLogger.info "[SMS_INVITATION] Sending invitation to customer #{customer.id} for business #{business&.safe_identifier_for_logging} (#{context})"

    # Create invitation record
    invitation = SmsOptInInvitation.create!(
      phone_number: customer.phone,
      business: business,
      tenant_customer: customer,
      context: context.to_s,
      sent_at: Time.current
    )

    # Generate context-specific message
    message = generate_invitation_message(business, context)

    # Send the invitation SMS (bypass rate limiting for invitations)
    # Use the customer's business_id if the provided business is not persisted
    business_id = if business&.persisted?
      business.id
    else
      customer.business_id
    end

    result = send_message(customer.phone, message, {
      business_id: business_id,
      tenant_customer_id: customer.id
    })

    if result[:success]
      SecureLogger.info "[SMS_INVITATION] Invitation sent successfully to #{customer.phone} for business #{business.name}"
    else
      SecureLogger.error "[SMS_INVITATION] Failed to send invitation to #{customer.phone}: #{result[:error]}"
    end

    result
  end

  # Generate context-aware invitation message
  def self.generate_invitation_message(business, context)
    context_description = case context.to_sym
    when :booking_confirmation
      "booking confirmation"
    when :booking_reminder
      "booking reminder"
    when :order_confirmation, :order_update
      "order update"
    when :payment_reminder
      "payment reminder"
    else
      "notification"
    end

    "Hi! #{business.name} tried to send you a #{context_description}. " \
    "Reply YES to receive SMS from #{business.name} or STOP to opt out. " \
    "Msg & data rates may apply."
  end
end
