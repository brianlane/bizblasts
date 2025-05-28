# frozen_string_literal: true

# Configure Resend for email delivery
Resend.api_key = ENV['RESEND_API_KEY']

# Configure ActionMailer to use Resend
Rails.application.configure do
  config.action_mailer.delivery_method = :resend
  
  # Set default from address for all emails
  config.action_mailer.default_options = {
    from: ENV['MAILER_EMAIL']
  }
  
  # Enable email delivery in all environments
  config.action_mailer.perform_deliveries = true
  
  # Raise delivery errors in development and production for debugging
  config.action_mailer.raise_delivery_errors = true
end 