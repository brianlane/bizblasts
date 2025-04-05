class SmsService
  # This service handles sending SMS messages using a third-party provider (e.g., Twilio)
  
  def self.send_message(phone_number, message, options = {})
    # Check if the phone number is valid
    unless valid_phone_number?(phone_number)
      return { success: false, error: "Invalid phone number format" }
    end
    
    # Create an SMS message record
    sms_message = create_sms_record(phone_number, message, options)
    
    # In a real implementation, this would use the Twilio API or similar
    # client = Twilio::REST::Client.new(ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN'])
    # begin
    #   response = client.messages.create(
    #     from: ENV['TWILIO_PHONE_NUMBER'],
    #     to: phone_number,
    #     body: message
    #   )
    #   sms_message.update(
    #     status: :sent,
    #     sent_at: Time.current,
    #     external_id: response.sid
    #   )
    #   { success: true, sms_message: sms_message, external_id: response.sid }
    # rescue Twilio::REST::RestError => e
    #   sms_message.update(status: :failed, error_message: e.message)
    #   { success: false, error: e.message, sms_message: sms_message }
    # end
    
    # Placeholder implementation
    success = rand > 0.1 # 90% success rate for testing
    
    if success
      external_id = "SM#{SecureRandom.hex(10)}"
      sms_message.mark_as_sent!
      { success: true, sms_message: sms_message, external_id: external_id }
    else
      error_message = "Failed to send SMS (simulated failure)"
      sms_message.mark_as_failed!(error_message)
      { success: false, error: error_message, sms_message: sms_message }
    end
  end
  
  def self.send_booking_confirmation(booking)
    customer = booking.tenant_customer
    service = booking.service
    
    message = "Booking confirmed: #{service&.name || 'Appointment'} on #{booking.start_time.strftime('%b %d at %I:%M %p')}. " \
              "Reply HELP for assistance or CANCEL to cancel your appointment."
    
    send_message(customer.phone, message, { 
      tenant_customer_id: customer.id,
      booking_id: booking.id,
      business_id: booking.business_id
    })
  end
  
  def self.send_booking_reminder(booking, timeframe)
    customer = booking.tenant_customer
    service = booking.service
    
    message = "Reminder: Your #{service&.name || 'appointment'} is #{timeframe == '24h' ? 'tomorrow' : 'in 1 hour'} " \
              "at #{booking.start_time.strftime('%I:%M %p')}. " \
              "Reply HELP for assistance or CONFIRM to confirm."
    
    send_message(customer.phone, message, { 
      tenant_customer_id: customer.id,
      booking_id: booking.id,
      business_id: booking.business_id
    })
  end
  
  def self.process_webhook(params)
    # This would handle webhook callbacks from the SMS provider
    # For example, delivery receipts
    
    # Placeholder implementation
    message_id = params[:message_id]
    status = params[:status]
    
    sms_message = SmsMessage.find_by(external_id: message_id)
    return { success: false, error: "Message not found" } unless sms_message
    
    if status == "delivered"
      sms_message.mark_as_delivered!
      { success: true, sms_message: sms_message }
    elsif status == "failed"
      error = params[:error_message] || "Delivery failed"
      sms_message.mark_as_failed!(error)
      { success: false, error: error, sms_message: sms_message }
    else
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
