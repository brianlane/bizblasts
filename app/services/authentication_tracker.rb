# frozen_string_literal: true

# Service for tracking authentication events across the system
# Provides monitoring and analytics for auth flows
class AuthenticationTracker
  include ActiveSupport::Configurable

  # Event types for tracking
  AUTH_EVENTS = {
    # Bridge events
    bridge_created: 'auth_bridge_created',
    bridge_consumed: 'auth_bridge_consumed',
    bridge_failed: 'auth_bridge_failed',
    bridge_rate_limited: 'auth_bridge_rate_limited',

    # Session events
    session_created: 'session_created',
    session_invalidated: 'session_invalidated',
    session_blacklisted: 'session_blacklisted',
    session_restored: 'session_restored',

    # Security events
    suspicious_request: 'suspicious_request',
    device_mismatch: 'device_mismatch',
    rapid_requests: 'rapid_requests',
    invalid_token: 'invalid_token',

    # Cross-domain events
    cross_domain_success: 'cross_domain_success',
    cross_domain_failure: 'cross_domain_failure'
  }.freeze

  class << self
    # Track an authentication event
    # @param event_type [Symbol] The type of event from AUTH_EVENTS
    # @param user [User, nil] The user associated with the event
    # @param request [ActionDispatch::Request, nil] The HTTP request
    # @param metadata [Hash] Additional event metadata
    def track_event(event_type, user: nil, request: nil, **metadata)
      return unless enabled?

      event_name = AUTH_EVENTS[event_type]
      return unless event_name

      event_data = build_event_data(event_name, user, request, metadata)

      # Log the event
      log_event(event_data)

      # Send to monitoring if configured
      send_to_monitoring(event_data) if monitoring_enabled?

      # Store for analytics if configured
      store_for_analytics(event_data) if analytics_enabled?

      event_data
    rescue => e
      Rails.logger.error "[AuthTracker] Failed to track event #{event_type}: #{e.message}"
      nil
    end

    # Track successful auth bridge creation
    def track_bridge_created(user, target_url, business_id, request)
      track_event(:bridge_created,
        user: user,
        request: request,
        target_url: sanitize_url(target_url),
        business_id: business_id
      )
    end

    # Track successful auth bridge consumption
    def track_bridge_consumed(user, auth_token, request)
      track_event(:bridge_consumed,
        user: user,
        request: request,
        token_age: auth_token.created_at ? (Time.current - auth_token.created_at).round(2) : nil,
        target_domain: extract_domain(auth_token.target_url),
        device_fingerprint_match: auth_token.validate_device_fingerprint(request)
      )
    end

    # Track failed auth bridge attempts
    def track_bridge_failed(reason, request, user: nil, **metadata)
      track_event(:bridge_failed,
        user: user,
        request: request,
        failure_reason: reason,
        **metadata
      )
    end

    # Track session events
    def track_session_created(user, request)
      track_event(:session_created,
        user: user,
        request: request,
        session_token: user.session_token&.first(8) # Only log first 8 chars for privacy
      )
    end

    def track_session_invalidated(user, session_token, request)
      track_event(:session_invalidated,
        user: user,
        request: request,
        session_token: session_token&.first(8)
      )
    end

    def track_session_blacklisted(user, session_token, reason = 'logout')
      track_event(:session_blacklisted,
        user: user,
        session_token: session_token&.first(8),
        reason: reason
      )
    end

    # Track security events
    def track_suspicious_request(request, reason, user: nil)
      track_event(:suspicious_request,
        user: user,
        request: request,
        reason: reason
      )
    end

    def track_device_mismatch(user, auth_token, request)
      track_event(:device_mismatch,
        user: user,
        request: request,
        token_id: auth_token.id,
        expected_fingerprint: auth_token.device_fingerprint&.first(8),
        actual_fingerprint: auth_token.generate_device_fingerprint(request)&.first(8)
      )
    end

    # Track cross-domain authentication success
    def track_cross_domain_success(user, from_domain, to_domain, request)
      track_event(:cross_domain_success,
        user: user,
        request: request,
        from_domain: sanitize_domain(from_domain),
        to_domain: sanitize_domain(to_domain)
      )
    end

    private

    def enabled?
      Rails.application.config.x.auth_tracking&.enabled != false
    end

    def monitoring_enabled?
      Rails.application.config.x.auth_tracking&.monitoring_enabled == true
    end

    def analytics_enabled?
      Rails.application.config.x.auth_tracking&.analytics_enabled == true
    end

    def build_event_data(event_name, user, request, metadata)
      {
        event: event_name,
        timestamp: Time.current.iso8601,
        user_id: user&.id,
        user_role: user&.role,
        business_id: user&.business_id,
        ip_address: request ? SecurityConfig.client_ip(request) : nil,
        user_agent: sanitize_user_agent(request&.user_agent),
        host: request&.host,
        domain_type: determine_domain_type(request&.host),
        request_id: request&.request_id,
        session_id: request&.session&.id&.to_s&.first(8),
        **metadata
      }.compact
    end

    def log_event(event_data)
      Rails.logger.info "[AuthTracker] #{event_data[:event]}: #{event_data.except(:event).to_json}"
    end

    def send_to_monitoring(event_data)
      # Integration point for monitoring services (DataDog, New Relic, etc.)
      # This could be enhanced to send to external monitoring services
      Rails.logger.info "[AuthTracker:Monitor] #{event_data.to_json}"
    end

    def store_for_analytics(event_data)
      # Integration point for analytics storage
      # This could be enhanced to store in a dedicated analytics database
      Rails.logger.info "[AuthTracker:Analytics] #{event_data.to_json}"
    end

    def determine_domain_type(host)
      return nil unless host.present?

      if Rails.env.production?
        case host.downcase
        when 'bizblasts.com', 'www.bizblasts.com'
          'main'
        when /\A[^.]+\.bizblasts\.com\z/
          'subdomain'
        else
          'custom'
        end
      else
        case host.downcase
        when 'localhost', 'lvh.me', 'www.lvh.me', 'example.com', 'www.example.com', 'test.host'
          'main'
        when /\A[^.]+\.lvh\.me\z/, /\A[^.]+\.example\.com\z/
          'subdomain'
        else
          'custom'
        end
      end
    end

    def sanitize_url(url)
      return nil unless url.present?

      begin
        uri = URI.parse(url)
        # Check if we have a valid scheme and host
        if uri.scheme.present? && uri.host.present?
          "#{uri.scheme}://#{uri.host}#{uri.path.presence || '/'}"
        else
          '[invalid_url]'
        end
      rescue URI::InvalidURIError
        '[invalid_url]'
      end
    end

    def sanitize_domain(domain)
      return nil unless domain.present?
      # Remove script tags and other HTML-like patterns, then clean
      # Use loop to prevent nested injection attacks (e.g., <sc<script>ript>)
      cleaned = domain.to_s.downcase

      # Repeatedly remove anything between < and > (including nested tags)
      # This prevents nested injection where tags hide within other tags
      loop do
        before = cleaned
        # Remove complete HTML-like patterns including content between brackets
        cleaned = cleaned.gsub(/<[^>]*>/, '')
        break if before == cleaned
      end

      # Remove ALL remaining angle brackets (catches malformed tags)
      cleaned = cleaned.gsub(/[<>]/, '')

      # Remove non-allowed characters (whitelist approach)
      # This catches any other dangerous characters
      cleaned = cleaned.gsub(/[^a-z0-9.-]/, '')
      cleaned[0...100] # Use ... for exclusive range to get exactly 100 chars
    end

    def sanitize_user_agent(user_agent)
      return nil unless user_agent.present?
      user_agent.to_s[0...200] # Use ... for exclusive range to get exactly 200 chars
    end

    def extract_domain(url)
      return nil unless url.present?

      begin
        URI.parse(url).host
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end