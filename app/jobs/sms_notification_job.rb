class SmsNotificationJob < ApplicationJob
  queue_as :notifications

  def perform(phone_number, message, options = {})
    # Format the phone number
    formatted_phone = format_phone_number(phone_number)
    return if formatted_phone.blank?
    
    # Apply any template processing to the message
    final_message = process_message_template(message, options)
    return if final_message.blank?
    
    # Send the message using a third-party provider
    send_sms(formatted_phone, final_message, options)
  end
  
  private
  
  def format_phone_number(phone)
    # Basic phone number formatting
    # Strip non-numeric characters
    formatted = phone.to_s.gsub(/\D/, '')
    
    # Ensure it has enough digits
    return nil if formatted.length < 10
    
    # In a real app, you'd have more sophisticated phone validation and formatting
    # based on country codes, etc.
    
    # For US numbers, ensure it has country code
    formatted = "1#{formatted}" if formatted.length == 10
    
    "+#{formatted}"
  end
  
  def process_message_template(message, options)
    # This would handle any dynamic content in the message
    # In a real app, this might involve replacing tokens with actual values
    
    # Example placeholder implementation
    message
  end
  
  def send_sms(phone, message, options)
    # In a real implementation, this would use the Twilio API or similar
    # client = Twilio::REST::Client.new(ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN'])
    # 
    # begin
    #   response = client.messages.create(
    #     from: ENV['TWILIO_PHONE_NUMBER'],
    #     to: phone,
    #     body: message
    #   )
    #   
    #   # Log the successful send
    #   Rails.logger.info "SMS sent to #{phone} with SID: #{response.sid}"
    #   
    #   # Record in database if needed
    #   if options[:booking_id] || options[:customer_id] || options[:marketing_campaign_id]
    #     record_sms_in_database(phone, message, response.sid, options)
    #   end
    # rescue => e
    #   # Log the error
    #   Rails.logger.error "SMS failed to send to #{phone}: #{e.message}"
    #   
    #   # Record the failure
    #   record_sms_failure(phone, message, e.message, options)
    #   
    #   # Re-raise the error to trigger job retry if appropriate
    #   raise e if should_retry?(e)
    # end
    
    # Placeholder implementation
    puts "Sending SMS to #{phone}: #{message}"
    Rails.logger.info "Sending SMS to #{phone}: #{message}"
    
    # Record in database if needed
    if options[:booking_id] || options[:customer_id] || options[:marketing_campaign_id]
      record_sms_in_database(phone, message, "MOCK_SID_#{SecureRandom.hex(10)}", options)
    end
  end
  
  def record_sms_in_database(phone, message, sid, options)
    # Record the SMS in our database for tracking purposes
    sms = SmsMessage.find_or_initialize_by(
      phone_number: phone,
      content: message,
      booking_id: options[:booking_id],
      customer_id: options[:customer_id],
      marketing_campaign_id: options[:marketing_campaign_id],
      business_id: options[:business_id] || Current.business_id
    )
    
    sms.external_id = sid
    sms.status = :sent
    sms.sent_at = Time.current
    sms.save
  end
  
  def record_sms_failure(phone, message, error, options)
    # Record the SMS failure
    sms = SmsMessage.find_or_initialize_by(
      phone_number: phone,
      content: message,
      booking_id: options[:booking_id],
      customer_id: options[:customer_id],
      marketing_campaign_id: options[:marketing_campaign_id],
      business_id: options[:business_id] || Current.business_id
    )
    
    sms.status = :failed
    sms.error_message = error
    sms.save
  end
  
  def should_retry?(error)
    # Determine if this error type should trigger a retry
    # In a real app, you'd have logic to identify transient errors
    true
  end
end
