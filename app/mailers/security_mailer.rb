# frozen_string_literal: true

class SecurityMailer < ApplicationMailer
  def security_alert(event_type:, message:, timestamp:)
    @event_type = event_type
    @message = message
    @timestamp = timestamp
    
    admin_email = ENV['ADMIN_EMAIL']
    return unless admin_email.present?
    
    mail(
      to: admin_email,
      subject: "[SECURITY ALERT] #{event_type.to_s.humanize} - BizBlasts",
      from: 'team@bizblasts.com',
      reply_to: @support_email
    )
  end
end