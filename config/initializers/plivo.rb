# frozen_string_literal: true

# Plivo SMS Configuration
# Validates required environment variables and sets up global constants

begin
  PLIVO_AUTH_ID = ENV.fetch('PLIVO_AUTH_ID') { raise 'PLIVO_AUTH_ID environment variable not set' }
  PLIVO_AUTH_TOKEN = ENV.fetch('PLIVO_AUTH_TOKEN') { raise 'PLIVO_AUTH_TOKEN environment variable not set' }
  PLIVO_SOURCE_NUMBER = ENV.fetch('PLIVO_SOURCE_NUMBER') { raise 'PLIVO_SOURCE_NUMBER environment variable not set' }
  
  Rails.logger.info "Plivo SMS configured with source number: #{PLIVO_SOURCE_NUMBER}"
rescue => e
  Rails.logger.error "Plivo configuration error: #{e.message}"
  
  # In development/test, allow missing credentials with warnings
  if Rails.env.development? || Rails.env.test?
    Rails.logger.warn "Plivo SMS will not function without proper configuration"
    
    # Set placeholder values to prevent constant errors
    PLIVO_AUTH_ID = 'MISSING_PLIVO_AUTH_ID'
    PLIVO_AUTH_TOKEN = 'MISSING_PLIVO_AUTH_TOKEN'
    PLIVO_SOURCE_NUMBER = 'MISSING_PLIVO_SOURCE_NUMBER'
  else
    # In production, fail hard if credentials are missing
    raise e
  end
end