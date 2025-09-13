class SmsService
  # This service handles sending SMS messages using Twilio
  
  def self.send_message(phone_number, message, options = {})
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
  
  def self.send_booking_confirmation(booking)
    customer = booking.tenant_customer
    service = booking.service
    
    message = "Booking confirmed: #{service&.name || 'Booking'} on #{booking.local_start_time.strftime('%b %d at %I:%M %p')}. " \
              "Reply HELP for assistance or CANCEL to cancel your booking."
    
    send_message(customer.phone, message, { 
      tenant_customer_id: customer.id,
      booking_id: booking.id,
      business_id: booking.business_id
    })
  end
  
  def self.send_booking_reminder(booking, timeframe)
    customer = booking.tenant_customer
    service = booking.service
    
    message = "Reminder: Your #{service&.name || 'booking'} is #{timeframe == '24h' ? 'tomorrow' : 'in 1 hour'} " \
              "at #{booking.local_start_time.strftime('%I:%M %p')}. " \
              "Reply HELP for assistance or CONFIRM to confirm."
    
    send_message(customer.phone, message, { 
      tenant_customer_id: customer.id,
      booking_id: booking.id,
      business_id: booking.business_id
    })
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
  
  def self.valid_phone_number?(phone)
    # Very basic phone validation - this should be enhanced for production
    phone.present? && phone.gsub(/\D/, '').length >= 10
  end
  
  def self.create_sms_record(phone_number, content, options = {})
    # REMOVED: Business ID derivation - SmsMessage doesn't have business_id
    # business_id = options[:business_id] 
    # business_id ||= TenantCustomer.find_by(id: options[:tenant_customer_id])&.business_id
    # business_id ||= Booking.find_by(id: options[:booking_id])&.business_id
    # business_id ||= MarketingCampaign.find_by(id: options[:marketing_campaign_id])&.business_id
    
    SmsMessage.create(
      phone_number: phone_number,
      content: content,
      status: :pending,
      tenant_customer_id: options[:tenant_customer_id],
      booking_id: options[:booking_id],
      marketing_campaign_id: options[:marketing_campaign_id]
      # REMOVED: business_id: business_id 
    )
  end
end
