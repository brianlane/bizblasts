# frozen_string_literal: true

# Mailer for custom domain setup notifications
# Handles setup instructions, success notifications, and timeout help
class DomainMailer < ApplicationMailer
  default from: "BizBlasts Support <#{ENV.fetch('SUPPORT_EMAIL', 'bizblaststeam@gmail.com')}>"

  # Send CNAME setup instructions to business owner
  def setup_instructions(business, user)
    @business = business
    @user = user
    @domain = business.hostname
    @render_target = Rails.env.production? ? 'bizblasts.onrender.com' : 'localhost'
    @support_email = ENV.fetch('SUPPORT_EMAIL', 'bizblaststeam@gmail.com')

    mail(
      to: @user.email,
      subject: "Custom Domain Setup Instructions for #{@business.name}",
      reply_to: @support_email
    )
  end

  # Notify when domain activation is successful
  def activation_success(business, user)
    @business = business
    @user = user
    @domain = business.hostname
    @domain_url = "https://#{@domain}"

    mail(
      to: @user.email,
      subject: "🎉 Your custom domain #{@domain} is now active!",
      reply_to: ENV.fetch('SUPPORT_EMAIL', 'bizblaststeam@gmail.com')
    )
  end

  # Send help when domain setup times out
  def timeout_help(business, user)
    @business = business
    @user = user
    @domain = business.hostname
    @render_target = Rails.env.production? ? 'bizblasts.onrender.com' : 'localhost'
    @support_email = ENV.fetch('SUPPORT_EMAIL', 'bizblaststeam@gmail.com')

    mail(
      to: @user.email,
      subject: "Help needed: Custom domain setup for #{@domain}",
      reply_to: @support_email
    )
  end

  # Notify when monitoring is manually restarted
  def monitoring_restarted(business, user)
    @business = business
    @user = user
    @domain = business.hostname

    mail(
      to: @user.email,
      subject: "Domain monitoring restarted for #{@domain}",
      reply_to: ENV.fetch('SUPPORT_EMAIL', 'bizblaststeam@gmail.com')
    )
  end
end