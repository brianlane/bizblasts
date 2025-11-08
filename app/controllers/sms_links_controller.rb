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

    # Track the click
    sms_link.increment!(:click_count)
    sms_link.update!(last_clicked_at: Time.current)

    Rails.logger.info "[SMS_LINK] Redirecting #{short_code} to #{sms_link.original_url} (click ##{sms_link.click_count})"
    SecureLogger.info "[SMS_LINK_SUCCESS] Short code '#{short_code}' → #{sms_link.original_url} (clicks: #{sms_link.click_count})"

    # Redirect to the original URL with 301 for SEO/caching
    redirect_to sms_link.original_url, status: :moved_permanently, allow_other_host: true

  rescue => e
    Rails.logger.error "[SMS_LINK] Error handling redirect for #{short_code}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    SecureLogger.error "[SMS_LINK_ERROR] Failed to redirect '#{short_code}': #{e.message}"

    # Return error page instead of redirect
    render plain: "Error processing link", status: :internal_server_error
  end
end