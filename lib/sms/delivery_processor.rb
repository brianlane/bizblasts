module Sms
  class DeliveryProcessor
    # DEPRECATED: This class is deprecated in favor of SmsService
    # It's kept for backwards compatibility but delegates to SmsService
    
    def self.process_delivery(phone_number, message, options = {})
      # Delegate to SmsService for actual delivery
      Rails.logger.warn "Sms::DeliveryProcessor.process_delivery is deprecated - use SmsService.send_message instead"
      
      result = SmsService.send_message(phone_number, message, options)
      result[:success]
    end
    
    def self.validate_phone_number(phone_number)
      # Delegate to SmsService for validation
      Rails.logger.warn "Sms::DeliveryProcessor.validate_phone_number is deprecated - use SmsService validation instead"
      
      phone_number.present? && phone_number.gsub(/\D/, '').length >= 10
    end
    
    def self.delivery_status(delivery_id)
      # Check delivery status by looking up SmsMessage by external_id
      Rails.logger.warn "Sms::DeliveryProcessor.delivery_status is deprecated - use SmsMessage.find_by(external_id: id).status instead"
      
      sms_message = SmsMessage.find_by(external_id: delivery_id)
      return :unknown unless sms_message
      
      sms_message.status.to_sym
    end
  end
end
