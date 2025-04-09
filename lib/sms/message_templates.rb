module Sms
  class MessageTemplates
    def self.reminder_template
      "Reminder: You have an booking on %DATE% at %TIME% with %BUSINESS_NAME%."
    end
    
    def self.confirmation_template
      "Your booking for %SERVICE_NAME% has been confirmed for %DATE% at %TIME%."
    end
    
    def self.cancellation_template
      "Your booking on %DATE% at %TIME% has been cancelled."
    end
    
    def self.update_template
      "Your booking has been updated to %DATE% at %TIME%."
    end
  end
end
