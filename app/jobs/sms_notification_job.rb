class SmsNotificationJob < ApplicationJob
  queue_as :notifications

  def perform(phone_number, message, options = {})
    # Early return if SMS is globally disabled
    unless Rails.application.config.sms_enabled
      Rails.logger.info "[SMS_NOTIFICATION_JOB] SMS disabled globally, skipping job for #{phone_number}"
      return
    end
    
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
    # Delegate to SmsService for actual SMS sending
    result = SmsService.send_message(phone, message, options)
    
    if result[:success]
      Rails.logger.info "SMS sent successfully to #{phone} via SmsService"
    else
      Rails.logger.error "SMS failed to send to #{phone}: #{result[:error]}"
      
      # Re-raise error to trigger job retry if appropriate
      raise StandardError, result[:error] if should_retry?(result[:error])
    end
    
    result
  end
  
  # SMS database recording is now handled by SmsService
  # These methods are kept for backwards compatibility but deprecated
  
  def record_sms_in_database(phone, message, sid, options)
    # DEPRECATED: SmsService now handles database recording
    Rails.logger.warn "record_sms_in_database is deprecated - SmsService handles this automatically"
  end
  
  def record_sms_failure(phone, message, error, options)
    # DEPRECATED: SmsService now handles database recording
    Rails.logger.warn "record_sms_failure is deprecated - SmsService handles this automatically"
  end
  
  def should_retry?(error_message)
    # Determine if this error type should trigger a retry
    # Retry transient errors but not permanent ones
    return false if error_message.include?("Invalid phone number")
    return false if error_message.include?("Unauthorized")
    return false if error_message.include?("Forbidden")
    
    # Retry for temporary issues
    return true if error_message.include?("timeout")
    return true if error_message.include?("rate limit")
    return true if error_message.include?("server error")
    
    # Default: retry most errors
    true
  end
end
