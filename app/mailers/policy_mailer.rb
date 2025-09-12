# frozen_string_literal: true

class PolicyMailer < ApplicationMailer
  def policy_update_notification(user, updated_policies)
    @user = user
    @updated_policies = updated_policies
    @support_email = ENV.fetch('SUPPORT_EMAIL', 'bizblaststeam@gmail.com')
    
    mail(
      to: user.email,
      subject: "Important: BizBlasts Policy Updates - Action Required",
      reply_to: @support_email
    )
  end
end 