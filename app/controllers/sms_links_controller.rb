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
    
    # Track the click
    sms_link.increment!(:click_count)
    sms_link.update!(last_clicked_at: Time.current)
    
    Rails.logger.info "[SMS_LINK] Redirecting #{short_code} to #{sms_link.original_url} (click ##{sms_link.click_count})"
    
    # Redirect to the original URL (may be on a different tenant host)
    redirect_to sms_link.original_url,
                status: :moved_permanently,
                allow_other_host: true
    
  rescue => e
    Rails.logger.error "[SMS_LINK] Error handling redirect for #{short_code}: #{e.message}"
    redirect_to root_path, alert: "Error processing link"
  end
end