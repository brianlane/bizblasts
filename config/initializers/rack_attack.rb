# frozen_string_literal: true

# SECURITY FIX: Rate limiting configuration with rack-attack

class Rack::Attack
  # Use Rails.cache for all environments (no Redis dependency)
  Rack::Attack.cache.store = Rails.cache

  # Development and test only. Do not safelist loopback in production:
  # Caddy connects from 127.0.0.1, and before visitor IPs were restored
  # every public request shared that address.
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

  # Throttle rental booking creation to prevent spam/abuse
  throttle('rental_bookings/ip', limit: 5, period: 1.hour) do |req|
    req.ip if req.path.match?(%r{/rentals/\d+/create_booking}) && req.post?
  end

  # SECURITY: Throttle Place ID extraction to prevent DoS via headless browser
  # Limit: 5 extractions per hour per IP (in addition to user-based limit in controller)
  throttle('place_id_extraction/ip', limit: 5, period: 1.hour) do |req|
    req.ip if req.path == '/manage/settings/integrations/lookup-place-id' && req.post?
  end

  # Per visitor, after Middleware::LocalProxyClientIp. Assets, Action Cable,
  # and health checks are excluded. 100/minute is the burst cap and
  # 300/5 minutes is the sustained cap for HTML and XHR once each visitor
  # has their own address. They are left as-is: a person browsing stays
  # under them, and a scanner on one IP still gets cut off.
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip unless req.path.start_with?('/assets', '/cable', '/up', '/healthcheck')
  end

  # Exponential backoff for repeat offenders
  throttle('req/ip/exponential', limit: 100, period: 1.minute) do |req|
    req.ip unless req.path.start_with?('/assets', '/cable', '/up', '/healthcheck')
  end

  # rack-attack 6.x passes a Rack::Attack::Request, not the env hash.
  # A bug in this block must still return 429. Raising here is what turned
  # the November 2026 throttle into a site-wide 500.
  def self.throttled_retry_after(request)
    match_data = rack_attack_match_data(request)
    return nil unless match_data.is_a?(Hash)

    period = Integer(match_data[:period] || match_data['period'])
    now = Integer(match_data[:epoch_time] || match_data['epoch_time'])
    return nil unless period.positive?

    remaining = period - (now % period)
    remaining.positive? ? remaining : period
  rescue ArgumentError, TypeError
    nil
  end

  def self.rack_attack_match_data(request)
    env = request.respond_to?(:env) ? request.env : request
    return nil unless env.respond_to?(:[])

    env['rack.attack.match_data']
  end

  def self.throttled_response_for(request)
    retry_after = throttled_retry_after(request)
    body = { error: 'Rate limit exceeded. Please try again later.' }.to_json
    headers = { 'Content-Type' => 'application/json' }
    headers['Retry-After'] = retry_after.to_s if retry_after
    [429, headers, [body]]
  end

  def self.plain_throttled_response
    [429, { 'Content-Type' => 'text/plain' }, ["Rate limit exceeded. Please try again later.\n"]]
  end

  self.throttled_responder = lambda do |request|
    throttled_response_for(request)
  rescue StandardError => e
    begin
      Rails.logger.error("[RACK_ATTACK] throttled_responder failed open: #{e.class}: #{e.message}")
    rescue StandardError
      nil
    end
    plain_throttled_response
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