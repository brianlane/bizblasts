# frozen_string_literal: true

# SecureLogger - A utility class for logging sensitive data safely
# Automatically redacts personal information from log messages
class SecureLogger
  SENSITIVE_PATTERNS = {
    email: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
    # Process credit cards first to avoid phone regex matching parts of them
    credit_card: /\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/,
    # Enhanced phone pattern to match various formats with negative lookahead to avoid matching credit cards:
    # - 555-123-4567, (602) 686-6672, +1-555-123-4567, +16026866672, 1 (555) 123-4567
    # Negative lookahead (?!\d) ensures we don't match within longer digit sequences (like credit cards)
    phone: /(?<!\d)(\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}(?!\d)/,
    ssn: /\b\d{3}-?\d{2}-?\d{4}\b/,
    api_key: /\b[A-Za-z0-9]{20,}\b/
  }.freeze

  class << self
    def sanitize_message(message)
      return message unless message.is_a?(String)
      
      sanitized = message.dup
      
      SENSITIVE_PATTERNS.each do |type, pattern|
        sanitized.gsub!(pattern) do |match|
          case type
          when :email
            "#{match[0..2]}***@***"
          when :phone
            "***-***-#{match[-4..-1]}"
          else
            "[REDACTED_#{type.upcase}]"
          end
        end
      end
      
      sanitized
    end

    def info(message)
      Rails.logger.info(sanitize_message(message))
    end

    def warn(message)
      Rails.logger.warn(sanitize_message(message))
    end

    def error(message)
      Rails.logger.error(sanitize_message(message))
    end

    def debug(message)
      Rails.logger.debug(sanitize_message(message))
    end

    def security_event(event_type, details = {})
      timestamp = Time.current.iso8601
      ip = details.delete(:ip) || 'unknown'
      user_id = details.delete(:user_id) || 'anonymous'
      
      message = "[SECURITY_EVENT] #{event_type.upcase} at #{timestamp} - User: #{user_id}, IP: #{ip}"
      
      unless details.empty?
        sanitized_details = details.map { |k, v| "#{k}: #{sanitize_message(v.to_s)}" }.join(', ')
        message += " - #{sanitized_details}"
      end
      
      Rails.logger.warn(message)
      
      # Send email alert for critical events if configured
      send_security_alert(event_type, message) if critical_event?(event_type)
    end

    private

    def critical_event?(event_type)
      %w[unauthorized_access cross_tenant_attempt admin_impersonation].include?(event_type.to_s)
    end

    def send_security_alert(event_type, message)
      return unless ENV['ADMIN_EMAIL'].present?
      
      SecurityMailer.security_alert(
        event_type: event_type,
        message: message,
        timestamp: Time.current
      ).deliver_later
    rescue => e
      Rails.logger.error "[SecureLogger] Failed to send security alert: #{e.message}"
    end
  end
end