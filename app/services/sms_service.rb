class SmsService
  # This service handles sending SMS messages using Plivo
  
  def self.send_message(phone_number, message, options = {})
    # Check if the phone number is valid
    unless valid_phone_number?(phone_number)
      return { success: false, error: "Invalid phone number format" }
    end
    
    # Create an SMS message record
    sms_message = create_sms_record(phone_number, message, options)
    
    # Send SMS via Plivo API
    begin
      client = Plivo::RestClient.new(PLIVO_AUTH_ID, PLIVO_AUTH_TOKEN)
      response = client.messages.create(
        src: PLIVO_SOURCE_NUMBER,
        dst: phone_number,
        text: message
      )
      
      # Plivo returns message_uuid array. Validate it's present and not empty.
      message_uuids = response.message_uuid
      if message_uuids.nil? || message_uuids.empty?
        raise StandardError, "Plivo did not return a message UUID"
      end

      external_id = message_uuids.first
      
      sms_message.update!(
        status: :sent,
        sent_at: Time.current,
        external_id: external_id
      )
      
      Rails.logger.info "SMS sent successfully to #{phone_number} with Plivo UUID: #{external_id}"
      { success: true, sms_message: sms_message, external_id: external_id }
      
    rescue Plivo::Exceptions::PlivoRESTError => e
      error_message = "Plivo API error: #{e.message}"
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
    # Handle Plivo webhook callbacks for delivery receipts
    # Plivo sends MessageUUID in the webhook payload
    
    message_uuid = params[:MessageUUID] || params['MessageUUID']
    status = params[:Status] || params['Status']
    
    return { success: false, error: "Missing MessageUUID in webhook" } unless message_uuid
    return { success: false, error: "Missing Status in webhook" } unless status
    
    sms_message = SmsMessage.find_by(external_id: message_uuid)
    return { success: false, error: "Message not found for UUID: #{message_uuid}" } unless sms_message
    
    Rails.logger.info "Processing Plivo webhook for message #{message_uuid} with status: #{status}"
    
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
    when "sent", "queued"
      # These are intermediate states, don't update our status
      { success: true, status: "acknowledged", sms_message: sms_message }
    else
      Rails.logger.warn "Unknown Plivo status received: #{status}"
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
