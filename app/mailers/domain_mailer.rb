# frozen_string_literal: true

# Mailer for custom domain setup notifications
# Handles setup instructions, success notifications, and timeout help
class DomainMailer < ApplicationMailer
  # Use the same verified sender as other mailers, but with BizBlasts Support name
  #default from: "BizBlasts Support <#{ENV.fetch('MAILER_EMAIL', 'team@bizblasts.com')}>"

  # Send CNAME setup instructions to business owner
  def setup_instructions(business, user)
    @business = business
    @user = user
    @domain = business.hostname
    # Guard: a BizBlasts sub-domain is mandatory. Abort if missing to avoid
    # sending incorrect DNS instructions.
    unless business.subdomain.present?
      Rails.logger.error("[DomainMailer] Cannot send setup instructions – business ##{business.id} has no subdomain")
      raise ArgumentError, 'Business subdomain is blank'
    end

    @render_target = Rails.env.production? ? "#{business.subdomain}.bizblasts.com" : 'localhost'
    @support_email = ENV.fetch('SUPPORT_EMAIL', 'bizblaststeam@gmail.com')

    # Always instruct users to point the 'www' host at BizBlasts
    @cname_name = 'www'

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
    unless business.subdomain.present?
      Rails.logger.error("[DomainMailer] Cannot send timeout help – business ##{business.id} has no subdomain")
      raise ArgumentError, 'Business subdomain is blank'
    end

    @render_target = Rails.env.production? ? "#{business.subdomain}.bizblasts.com" : 'localhost'
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
    @render_target = Rails.env.production? ? "#{business.subdomain}.bizblasts.com" : 'localhost'

    mail(
      to: @user.email,
      subject: "Domain monitoring restarted for #{@domain}",
      reply_to: ENV.fetch('SUPPORT_EMAIL', 'bizblaststeam@gmail.com')
    )
  end
end