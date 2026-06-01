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

    assign_dns_instructions!
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

    assign_dns_instructions!
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
    # Guard: a BizBlasts sub-domain is mandatory. Abort if missing to avoid
    # sending incorrect DNS instructions.
    unless business.subdomain.present?
      Rails.logger.error("[DomainMailer] Cannot send monitoring restart notification – business ##{business.id} has no subdomain")
      raise ArgumentError, 'Business subdomain is blank'
    end

    assign_dns_instructions!

    mail(
      to: @user.email,
      subject: "Domain monitoring restarted for #{@domain}",
      reply_to: ENV.fetch('SUPPORT_EMAIL', 'bizblaststeam@gmail.com')
    )
  end

  private

  # Provider-aware DNS instructions. Sets:
  #   @dns_provider          - 'caddy' or 'render'
  #   @dns_apex_target_ip    - the IP the apex (@) A-record should point at
  #   @dns_www_target_type   - 'A' or 'CNAME'
  #   @dns_www_target_value  - the value for the www record
  #   @render_target         - legacy alias kept so older partials don't NPE
  #
  # Raises if we're on Caddy but can't resolve a real public IP. Sending a
  # placeholder ("contact support") would tell the customer to enter
  # invalid text into their DNS panel and would also leave
  # CnameDnsChecker.expected_apex_ip nil so DNS verification could never
  # succeed (Bugbot MEDIUM: "Placeholder IP blocks verification"). Failing
  # the mail send surfaces the operator misconfiguration loudly instead.
  def assign_dns_instructions!
    if defined?(DomainProvider) && DomainProvider.caddy?
      ip = bizblasts_public_ip
      if ip.blank?
        Rails.logger.error "[DomainMailer] refusing to send DNS instructions: BIZBLASTS_PUBLIC_IP unset and bizblasts.com A-record lookup failed"
        raise ArgumentError, 'BizBlasts public IP is not configured (set BIZBLASTS_PUBLIC_IP or ensure bizblasts.com has a public A record)'
      end

      @dns_provider          = 'caddy'
      @dns_apex_target_ip    = ip
      @dns_www_target_type   = 'A'
      @dns_www_target_value  = ip
      @render_target         = 'bizblasts.com'
    else
      @dns_provider          = 'render'
      @dns_apex_target_ip    = '216.24.57.1'
      @dns_www_target_type   = 'CNAME'
      @dns_www_target_value  = Rails.env.production? ? 'bizblasts.onrender.com' : 'localhost'
      @render_target         = @dns_www_target_value
    end
  end

  def bizblasts_public_ip
    return ENV['BIZBLASTS_PUBLIC_IP'].strip if ENV['BIZBLASTS_PUBLIC_IP'].present?

    require 'resolv'
    Resolv::DNS.open do |r|
      r.getresources('bizblasts.com', Resolv::DNS::Resource::IN::A).first&.address&.to_s
    end
  rescue StandardError
    nil
  end
end