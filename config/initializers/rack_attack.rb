# frozen_string_literal: true

# SECURITY FIX: Rate limiting configuration with rack-attack

class Rack::Attack
  # Use Rails.cache for all environments (no Redis dependency)
  Rack::Attack.cache.store = Rails.cache

  # Always allow requests from localhost in development
  safelist('allow from localhost') do |req|
    (Rails.env.development? || Rails.env.test?) && ['127.0.0.1', '::1'].include?(req.ip)
  end

  # Block requests from known bad IPs (add specific IPs as needed)
  # blocklist('block bad IPs') do |req|
  #   %w[1.2.3.4 5.6.7.8].include?(req.ip)
  # end

  # Throttle requests to contact form to prevent spam
  throttle('contact_form/ip', limit: 5, period: 1.hour) do |req|
    req.ip if req.path == '/contact' && req.post?
  end

  # Throttle search requests to prevent abuse
  throttle('search_req/ip', limit: 60, period: 1.minute) do |req|
    begin
      req.ip if req.path == '/businesses' && req.query_string&.include?('search')
    rescue => e
      Rails.logger.error "Error in Rack::Attack throttle: #{e.message}"
      nil
    end
  end

  # Throttle login attempts
  throttle('login_attempts/ip', limit: 10, period: 5.minutes) do |req|
    req.ip if req.path == '/users/sign_in' && req.post?
  end

  # Throttle registration attempts
  throttle('registration/ip', limit: 5, period: 1.hour) do |req|
    req.ip if (req.path.include?('sign_up') || req.path.include?('registrations')) && req.post?
  end

  # Throttle cart operations to prevent abuse
  throttle('cart_operations/ip', limit: 30, period: 1.minute) do |req|
    req.ip if req.path.include?('line_items') && (req.post? || req.patch?)
  end

  # Throttle password reset requests
  throttle('password_reset/ip', limit: 5, period: 1.hour) do |req|
    req.ip if req.path.include?('password') && req.post?
  end

  # SECURITY: Throttle Place ID extraction to prevent DoS via headless browser
  # Limit: 5 extractions per hour per IP (in addition to user-based limit in controller)
  throttle('place_id_extraction/ip', limit: 5, period: 1.hour) do |req|
    req.ip if req.path == '/manage/settings/integrations/lookup-place-id' && req.post?
  end

  # SECURITY: Throttle SMS link redirects to prevent click fraud/manipulation
  # Limit: 60 clicks per minute per IP (reasonable for legitimate SMS clicks)
  # This mitigates the lack of CSRF protection on this endpoint
  throttle('sms_link_clicks/ip', limit: 60, period: 1.minute) do |req|
    req.ip if req.path.start_with?('/s/') && req.get?
  end

  # General request throttling for potential DDoS protection
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip unless req.path.start_with?('/assets', '/cable', '/up', '/healthcheck')
  end

  # Exponential backoff for repeat offenders
  throttle('req/ip/exponential', limit: 100, period: 1.minute) do |req|
    req.ip unless req.path.start_with?('/assets', '/cable', '/up', '/healthcheck')
  end

  # Custom response for throttled requests
  self.throttled_responder = lambda do |env|
    retry_after = (env['rack.attack.match_data'] || {})[:period]
    
    [
      429,
      {
        'Content-Type' => 'application/json',
        'Retry-After' => retry_after.to_s
      },
      [{ error: 'Rate limit exceeded. Please try again later.' }.to_json]
    ]
  end

  # Log blocked requests
  ActiveSupport::Notifications.subscribe('rack.attack') do |name, start, finish, request_id, payload|
    begin
      req = payload[:request]
      Rails.logger.warn "[RACK_ATTACK] #{req.env['rack.attack.match_type']} #{req.ip} #{req.request_method} #{req.fullpath}"
    rescue => e
      Rails.logger.error "Error in Rack::Attack logging: #{e.message}"
    end
  end
end 