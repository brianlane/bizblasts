# frozen_string_literal: true

class PolicyMailer < ApplicationMailer
  def policy_update_notification(user, updated_policies)
    @user = user
    @updated_policies = updated_policies
    
    mail(
      to: user.email,
      subject: "Important: BizBlasts Policy Updates - Action Required"
    )
  end
end 