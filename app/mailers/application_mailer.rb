# frozen_string_literal: true

# Base mailer class for all application mailers
# Sets default from address and layout
class ApplicationMailer < ActionMailer::Base
  default from: ENV['MAILER_EMAIL']
  layout "mailer"
  # Include all helpers so that mailer views can access view helpers such as
  # service_with_variant, service_duration, etc.
  helper :application
  helper :unsubscribe
  
  # Override mail method to add logging
  def mail(headers = {}, &block)
    # Log the email details before sending
    Rails.logger.info "[EMAIL] Preparing #{self.class.name}##{action_name} to: #{headers[:to]} | Subject: #{headers[:subject]}"
    
    result = super(headers, &block)
    
    # Log successful email creation (note: this doesn't mean it was delivered)
    Rails.logger.info "[EMAIL] Mail object created successfully for #{headers[:to]} (delivery method: #{ActionMailer::Base.delivery_method})"
    
    result
  rescue => e
    Rails.logger.error "[EMAIL] Failed to create mail for #{headers[:to]}: #{e.message}"
    Rails.logger.error "[EMAIL] Error backtrace: #{e.backtrace.first(5).join("\n")}"
    raise
  end
  
  private
  
  # Add admin notice to email body
  def add_admin_notice(body)
    admin_notice = "\n\n---\nPlease do not reply to this email, and send all communications to #{ENV['ADMIN_EMAIL']}"
    body + admin_notice
  end

  # Set unsubscribe token for email recipient
  def set_unsubscribe_token(recipient)
    if recipient.is_a?(User)
      @unsubscribe_token = recipient.unsubscribe_token
      @user = recipient
    elsif recipient.is_a?(TenantCustomer)
      @unsubscribe_token = recipient.unsubscribe_token
      @user = nil
    else
      @unsubscribe_token = nil
      @user = nil
    end
  end
end
