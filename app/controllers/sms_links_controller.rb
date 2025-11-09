class SmsLinksController < ApplicationController
  # Public controller to handle SMS link redirects
  # Route: /s/:short_code

  # Skip tenant and authentication filters - this is a global redirect service
  skip_before_action :verify_allowed_host!, only: [:redirect]
  skip_before_action :set_tenant, only: [:redirect]
  skip_before_action :authenticate_user!, only: [:redirect], raise: false
  skip_before_action :verify_authenticity_token, only: [:redirect]
  skip_before_action :handle_cross_domain_authentication, only: [:redirect]
  skip_before_action :check_session_blacklist, only: [:redirect]

  def redirect
    short_code = params[:short_code]

    # Find the SMS link by short code
    sms_link = SmsLink.find_by(short_code: short_code)

    unless sms_link
      Rails.logger.warn "[SMS_LINK] Short code not found: #{short_code}"
      SecureLogger.warn "[SMS_LINK_404] Short code '#{short_code}' not found (referrer: #{request.referer})"

      # Return proper 404 response instead of redirect
      render plain: "Link not found", status: :not_found
      return
    end

    # Validate and sanitize URL before redirecting (defense in depth - model also validates)
    # Parse and reconstruct URL to ensure it's safe
    begin
      uri = URI.parse(sms_link.original_url)

      # Only allow http and https schemes (prevents javascript:, data:, file:, etc.)
      unless uri.scheme.in?(['http', 'https'])
        Rails.logger.error "[SMS_LINK] Invalid URL scheme for #{short_code}: #{uri.scheme}"
        SecureLogger.error "[SMS_LINK_INVALID] Short code '#{short_code}' has non-http(s) scheme"
        render plain: "Invalid link", status: :unprocessable_entity
        return
      end

      # Require a host (prevents malformed URLs)
      if uri.host.blank?
        Rails.logger.error "[SMS_LINK] Missing host for #{short_code}"
        SecureLogger.error "[SMS_LINK_INVALID] Short code '#{short_code}' has no host"
        render plain: "Invalid link", status: :unprocessable_entity
        return
      end

      # Reconstruct the URL to ensure it's properly formatted
      validated_url = uri.to_s
    rescue URI::InvalidURIError => e
      Rails.logger.error "[SMS_LINK] Invalid URL format for #{short_code}: #{e.message}"
      SecureLogger.error "[SMS_LINK_INVALID] Short code '#{short_code}' has invalid URL format"
      render plain: "Invalid link", status: :unprocessable_entity
      return
    end

    # Track the click
    sms_link.increment!(:click_count)
    sms_link.update!(last_clicked_at: Time.current)

    Rails.logger.info "[SMS_LINK] Redirecting #{short_code} to #{validated_url} (click ##{sms_link.click_count})"
    SecureLogger.info "[SMS_LINK_SUCCESS] Short code '#{short_code}' → #{validated_url} (clicks: #{sms_link.click_count})"

    # Redirect to the validated URL with 301 for SEO/caching
    # Security: URL has been parsed and validated inline above to only allow http/https URLs
    # brakeman:ignore:Redirect - URL is validated inline via URI.parse and scheme check
    redirect_to validated_url, status: :moved_permanently, allow_other_host: true

  rescue => e
    Rails.logger.error "[SMS_LINK] Error handling redirect for #{short_code}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    SecureLogger.error "[SMS_LINK_ERROR] Failed to redirect '#{short_code}': #{e.message}"

    # Return error page instead of redirect
    render plain: "Error processing link", status: :internal_server_error
  end
end