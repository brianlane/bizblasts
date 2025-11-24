class SmsLinkShortener
  # Simple URL shortening for SMS messages
  # In production, this could integrate with bit.ly, tinyurl, or custom shortener
  
  def self.shorten(full_url, tracking_params = {})
    return full_url if Rails.env.development? || Rails.env.test?
    
    # For now, use a simple approach - in production you'd integrate with a real service
    shortened_url = generate_short_url(full_url, tracking_params)
    
    # Store mapping for analytics and redirect handling
    SmsLink.create!(
      original_url: full_url,
      short_code: extract_short_code(shortened_url),
      tracking_params: tracking_params,
      created_at: Time.current
    )
    
    shortened_url
  rescue => e
    Rails.logger.error "[SMS_LINK_SHORTENER] Failed to shorten URL #{full_url}: #{e.message}"
    # Fallback to original URL if shortening fails
    full_url
  end

  def self.expand(short_code)
    link = SmsLink.find_by(short_code: short_code)
    return nil unless link
    
    # Track click
    link.increment!(:click_count)
    link.update!(last_clicked_at: Time.current)
    
    link.original_url
  end

  private

  def self.generate_short_url(full_url, tracking_params)
    # Generate a short code
    short_code = SecureRandom.alphanumeric(8).downcase
    
    # Ensure uniqueness
    while SmsLink.exists?(short_code: short_code)
      short_code = SecureRandom.alphanumeric(8).downcase
    end
    
    # Build short URL using main domain
    base_domain = Rails.env.production? ? 'bizblasts.com' : 'lvh.me:3000'
    protocol = Rails.env.production? ? 'https' : 'http'
    
    "#{protocol}://#{base_domain}/s/#{short_code}"
  end

  def self.extract_short_code(shortened_url)
    shortened_url.split('/').last
  end
end