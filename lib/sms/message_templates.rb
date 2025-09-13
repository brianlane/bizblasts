require 'yaml'

module Sms
  class MessageTemplates
    TEMPLATES = begin
      template_file = Rails.root.join('lib/sms/message_templates.yml')
      
      if File.exist?(template_file)
        YAML.load_file(template_file)
      else
        Rails.logger.error "[SMS_TEMPLATES] Template file not found: #{template_file}"
        # Provide minimal fallback templates
        {
          'system' => {
            'help_response' => 'Help: Text STOP to opt out. Contact support for assistance.',
            'opt_out_confirmation' => 'You have been unsubscribed from SMS messages.',
            'opt_in_confirmation' => 'You have been opted in to SMS messages.',
            'unknown_command' => "We didn't understand your message. Text HELP for assistance."
          },
          'booking' => {
            'confirmation' => 'Booking confirmed for %SERVICE_NAME% on %DATE% at %TIME%. Reply STOP to opt out.'
          }
        }
      end
    rescue => e
      Rails.logger.error "[SMS_TEMPLATES] Failed to load templates: #{e.message}"
      # Provide minimal fallback templates  
      {
        'system' => {
          'help_response' => 'Help: Text STOP to opt out. Contact support for assistance.',
          'opt_out_confirmation' => 'You have been unsubscribed from SMS messages.',
          'opt_in_confirmation' => 'You have been opted in to SMS messages.',
          'unknown_command' => "We didn't understand your message. Text HELP for assistance."
        },
        'booking' => {
          'confirmation' => 'Booking confirmed for %SERVICE_NAME% on %DATE% at %TIME%. Reply STOP to opt out.'
        }
      }
    end.freeze
    
    MAX_SMS_LENGTH = 160

    # Main method to render any template with variables
    def self.render(template_key, variables = {})
      template_path = template_key.to_s.split('.')
      template = TEMPLATES.dig(*template_path)
      
      return nil unless template
      
      message = interpolate_variables(template, variables)
      truncate_if_needed(message, MAX_SMS_LENGTH)
    end

    # Legacy methods for backward compatibility
    def self.reminder_template
      TEMPLATES.dig('booking', 'reminder')
    end
    
    def self.confirmation_template
      TEMPLATES.dig('booking', 'confirmation')
    end
    
    def self.cancellation_template
      TEMPLATES.dig('booking', 'cancellation')
    end
    
    def self.update_template
      TEMPLATES.dig('booking', 'status_update')
    end

    # Convenience methods for common templates
    def self.booking_confirmation(variables = {})
      render('booking.confirmation', variables)
    end

    def self.booking_reminder(variables = {})
      render('booking.reminder', variables)
    end

    def self.invoice_created(variables = {})
      render('invoice.created', variables)
    end

    def self.order_confirmation(variables = {})
      render('order.confirmation', variables)
    end

    def self.marketing_campaign(variables = {})
      render('marketing.campaign_promotional', variables)
    end

    private

    def self.interpolate_variables(template, variables)
      message = template.dup
      
      variables.each do |key, value|
        placeholder = "%#{key.to_s.upcase}%"
        message.gsub!(placeholder, value.to_s)
      end
      
      message
    end

    def self.truncate_if_needed(message, max_length)
      return message if message.length <= max_length
      
      # Truncate and add ellipsis, but preserve URLs if possible
      if message.include?('http')
        url_start = message.rindex('http')
        if url_start && url_start > max_length - 30
          # URL is near the end, truncate before URL and add it
          truncated = message[0...(max_length - (message.length - url_start + 4))]
          "#{truncated}... #{message[url_start..-1]}"
        else
          message[0...(max_length - 3)] + '...'
        end
      else
        message[0...(max_length - 3)] + '...'
      end
    end
  end
end
