# frozen_string_literal: true

# Base mailer class for all application mailers
# Sets default from address and layout
class ApplicationMailer < ActionMailer::Base
  default from: ENV['MAILER_EMAIL']
  layout "mailer"
  
  private
  
  # Add admin notice to email body
  def add_admin_notice(body)
    admin_notice = "\n\n---\nPlease do not reply to this email, and send all communications to #{ENV['ADMIN_EMAIL']}"
    body + admin_notice
  end
end
