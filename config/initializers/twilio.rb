# frozen_string_literal: true

# Twilio SMS Configuration
# Validates required environment variables and sets up global constants

begin
  TWILIO_ACCOUNT_SID = ENV.fetch('TWILIO_ACCOUNT_SID') { raise 'TWILIO_ACCOUNT_SID environment variable not set' }
  TWILIO_AUTH_TOKEN = ENV.fetch('TWILIO_AUTH_TOKEN') { raise 'TWILIO_AUTH_TOKEN environment variable not set' }
  TWILIO_MESSAGING_SERVICE_SID = ENV.fetch('TWILIO_MESSAGING_SERVICE_SID') { raise 'TWILIO_MESSAGING_SERVICE_SID environment variable not set' }
  
  Rails.logger.info "Twilio SMS configured with messaging service SID: #{TWILIO_MESSAGING_SERVICE_SID}"
rescue => e
  Rails.logger.error "Twilio configuration error: #{e.message}"
  
  # In development/test, allow missing credentials with warnings
  if Rails.env.development? || Rails.env.test?
    Rails.logger.warn "Twilio SMS will not function without proper configuration"
    
    # Set placeholder values to prevent constant errors
    TWILIO_ACCOUNT_SID = 'MISSING_TWILIO_ACCOUNT_SID'
    TWILIO_AUTH_TOKEN = 'MISSING_TWILIO_AUTH_TOKEN'
    TWILIO_MESSAGING_SERVICE_SID = 'MISSING_TWILIO_MESSAGING_SERVICE_SID'
  else
    # In production, fail hard if credentials are missing
    raise e
  end
end