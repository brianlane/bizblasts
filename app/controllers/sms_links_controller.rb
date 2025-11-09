class SmsLinksController < ApplicationController
  # Public controller to handle SMS link redirects
  # Route: /s/:short_code
  
  def redirect
    short_code = params[:short_code]
    
    # Find the SMS link by short code
    sms_link = SmsLink.find_by(short_code: short_code)
    
    unless sms_link
      Rails.logger.warn "[SMS_LINK] Short code not found: #{short_code}"
      redirect_to root_path, alert: "Link not found"
      return
    end
    
    # Ensure the stored URL is safe to redirect to
    safe_url = safe_redirect_url(sms_link.original_url)
    unless safe_url
      Rails.logger.warn "[SMS_LINK] Unsafe redirect attempted for #{short_code}: #{sms_link.original_url.inspect}"
      redirect_to root_path, alert: "Link not found"
      return
    end

    # Track the click
    sms_link.increment!(:click_count)
    sms_link.update!(last_clicked_at: Time.current)

    Rails.logger.info "[SMS_LINK] Redirecting #{short_code} to #{safe_url} (click ##{sms_link.click_count})"

    # Redirect to the original URL (may be on a different tenant host)
    redirect_to safe_url,
                status: :moved_permanently,
                allow_other_host: true
    
  rescue => e
    Rails.logger.error "[SMS_LINK] Error handling redirect for #{short_code}: #{e.message}"
    redirect_to root_path, alert: "Error processing link"
  end

  private

  def safe_redirect_url(url)
    uri = parse_http_uri(url)
    return unless uri && allowed_redirect_host?(uri.host)

    uri.to_s
  end

  def parse_http_uri(url)
    uri = URI.parse(url)
    return unless uri.is_a?(URI::HTTP) && uri.host.present?

    uri
  rescue URI::InvalidURIError
    nil
  end

  def allowed_redirect_host?(host)
    normalized_host = host.to_s.downcase
    return false if normalized_host.blank?

    return true if TenantHost.main_domain?(normalized_host)
    return true if business_hostname_allowed?(normalized_host)
    return true if matches_managed_subdomain?(normalized_host)

    false
  end

  def business_hostname_allowed?(host)
    return false unless businesses_table_available?

    Business.where('LOWER(hostname) = ?', host).exists?
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.warn "[SMS_LINK] Failed hostname check for #{host}: #{e.class}: #{e.message}"
    false
  end

  def matches_managed_subdomain?(host)
    allowed_subdomain_roots.any? do |root|
      next false unless host.end_with?(".#{root}")

      subdomain = host.delete_suffix(".#{root}")
      next false if subdomain.blank? || subdomain == 'www'

      business_with_subdomain?(subdomain)
    end
  end

  def business_with_subdomain?(subdomain)
    return false unless businesses_table_available?

    Business.where('LOWER(subdomain) = ?', subdomain.downcase).exists?
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.warn "[SMS_LINK] Failed subdomain check for #{subdomain}: #{e.class}: #{e.message}"
    false
  end

  def businesses_table_available?
    return @businesses_table_available unless @businesses_table_available.nil?

    @businesses_table_available = Business.table_exists?
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid => e
    Rails.logger.warn "[SMS_LINK] Businesses table check failed: #{e.class}: #{e.message}"
    @businesses_table_available = false
  end

  def allowed_subdomain_roots
    @allowed_subdomain_roots ||= begin
      configured = Rails.application.config.main_domain.to_s.split(':').first
      static_roots = %w[bizblasts.com bizblasts.onrender.com lvh.me]
      env_roots = ENV.fetch('SMS_LINK_ALLOWED_BASE_DOMAINS', nil)
      additional = env_roots.to_s.split(',').map { |domain| domain.strip.downcase }.reject(&:blank?)

      ([configured] + static_roots + additional).compact.map { |domain| domain.sub(/\A\./, '').downcase }.uniq
    end
  end
end
