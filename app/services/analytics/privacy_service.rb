# frozen_string_literal: true

module Analytics
  # Service for handling analytics privacy controls
  # Implements privacy-first approach with DNT respect and data deletion
  class PrivacyService
    attr_reader :business

    def initialize(business = nil)
      @business = business
    end

    # Check if tracking should be disabled based on request
    # @param request [ActionDispatch::Request] The HTTP request
    # @return [Boolean] true if tracking should be disabled
    def should_disable_tracking?(request)
      return true if do_not_track?(request)
      return true if bot_request?(request)
      return true if internal_request?(request)
      
      false
    end

    # Check Do Not Track header
    # @param request [ActionDispatch::Request] The HTTP request
    # @return [Boolean] true if DNT is set
    def do_not_track?(request)
      dnt = request.headers['DNT'] || request.headers['Dnt'] || request.headers['dnt']
      dnt == '1'
    end

    # Check if request is from a known bot
    # @param request [ActionDispatch::Request] The HTTP request
    # @return [Boolean] true if request appears to be from a bot
    def bot_request?(request)
      user_agent = request.user_agent.to_s.downcase
      
      bot_patterns = [
        'bot', 'crawler', 'spider', 'scraper', 'wget', 'curl',
        'googlebot', 'bingbot', 'slurp', 'duckduckbot', 'baiduspider',
        'yandexbot', 'facebookexternalhit', 'twitterbot', 'linkedinbot',
        'whatsapp', 'telegrambot', 'applebot', 'semrushbot', 'ahrefsbot',
        'mj12bot', 'dotbot', 'petalbot', 'screaming frog'
      ]
      
      bot_patterns.any? { |pattern| user_agent.include?(pattern) }
    end

    # Check if request is internal/monitoring
    # @param request [ActionDispatch::Request] The HTTP request
    # @return [Boolean] true if request is internal
    def internal_request?(request)
      # Check for internal monitoring headers
      request.headers['X-Health-Check'].present? ||
        request.headers['X-Internal-Request'].present?
    end

    # Generate privacy-respecting visitor fingerprint
    # Does not track across sessions and is not unique enough for cross-site tracking
    # @param request [ActionDispatch::Request] The HTTP request
    # @return [String] Anonymous fingerprint hash
    def generate_fingerprint(request)
      components = [
        request.user_agent.to_s[0..100], # Truncated user agent
        request.headers['Accept-Language'].to_s.split(',').first, # Primary language
        Time.current.to_date.to_s # Date-based salt for daily rotation
      ]
      
      Digest::SHA256.hexdigest(components.join('|'))[0..15]
    end

    # Anonymize IP address for privacy
    # @param ip [String] IP address to anonymize
    # @return [String] Anonymized IP address
    def anonymize_ip(ip)
      return nil if ip.blank?
      
      if ip.include?(':')
        # IPv6: zero out last 80 bits (keep first 48 bits)
        parts = ip.split(':')
        (parts[0..2] + ['0', '0', '0', '0', '0']).join(':')
      else
        # IPv4: zero out last octet
        parts = ip.split('.')
        (parts[0..2] + ['0']).join('.')
      end
    end

    # Delete all analytics data for a visitor (GDPR right to erasure)
    # @param visitor_fingerprint [String] The visitor fingerprint to delete
    # @return [Hash] Summary of deleted records
    def delete_visitor_data(visitor_fingerprint)
      return { error: 'Business context required' } unless business.present?
      return { error: 'Fingerprint required' } if visitor_fingerprint.blank?
      
      ActsAsTenant.with_tenant(business) do
        deleted = {
          page_views: 0,
          click_events: 0,
          visitor_sessions: 0
        }
        
        # Delete page views
        deleted[:page_views] = business.page_views
          .where(visitor_fingerprint: visitor_fingerprint)
          .delete_all
        
        # Delete click events
        deleted[:click_events] = business.click_events
          .where(visitor_fingerprint: visitor_fingerprint)
          .delete_all
        
        # Delete visitor sessions
        deleted[:visitor_sessions] = business.visitor_sessions
          .where(visitor_fingerprint: visitor_fingerprint)
          .delete_all
        
        Rails.logger.info "[Privacy] Deleted data for visitor #{visitor_fingerprint[0..8]}***: #{deleted.inspect}"
        
        deleted
      end
    end

    # Export all analytics data for a visitor (GDPR data portability)
    # @param visitor_fingerprint [String] The visitor fingerprint to export
    # @return [Hash] All visitor data in JSON format
    def export_visitor_data(visitor_fingerprint)
      return { error: 'Business context required' } unless business.present?
      return { error: 'Fingerprint required' } if visitor_fingerprint.blank?
      
      ActsAsTenant.with_tenant(business) do
        {
          visitor_fingerprint: visitor_fingerprint,
          exported_at: Time.current.iso8601,
          business_name: business.name,
          page_views: business.page_views
            .where(visitor_fingerprint: visitor_fingerprint)
            .order(created_at: :desc)
            .limit(1000)
            .map { |pv| sanitize_page_view_for_export(pv) },
          click_events: business.click_events
            .where(visitor_fingerprint: visitor_fingerprint)
            .order(created_at: :desc)
            .limit(1000)
            .map { |ce| sanitize_click_event_for_export(ce) },
          sessions: business.visitor_sessions
            .where(visitor_fingerprint: visitor_fingerprint)
            .order(session_start: :desc)
            .limit(100)
            .map { |s| sanitize_session_for_export(s) }
        }
      end
    end

    # Get tracking consent requirements based on visitor location
    # @param country_code [String] Two-letter country code
    # @return [Hash] Consent requirements
    def consent_requirements(country_code)
      gdpr_countries = %w[
        AT BE BG HR CY CZ DK EE FI FR DE GR HU IE IT LV LT LU MT NL PL PT RO SK SI ES SE
        GB IS LI NO CH
      ]
      
      ccpa_states = %w[CA] # California
      
      {
        requires_explicit_consent: gdpr_countries.include?(country_code.to_s.upcase),
        ccpa_applies: country_code.to_s.upcase == 'US', # Simplified - would need state detection
        tracking_allowed_by_default: !gdpr_countries.include?(country_code.to_s.upcase),
        opt_out_required: true # Always allow opt-out
      }
    end

    private

    def sanitize_page_view_for_export(page_view)
      {
        page_path: page_view.page_path,
        page_type: page_view.page_type,
        visited_at: page_view.created_at.iso8601,
        time_on_page: page_view.time_on_page,
        device_type: page_view.device_type,
        referrer_domain: page_view.referrer_domain
      }
    end

    def sanitize_click_event_for_export(click_event)
      {
        page_path: click_event.page_path,
        element_type: click_event.element_type,
        category: click_event.category,
        action: click_event.action,
        clicked_at: click_event.created_at.iso8601
      }
    end

    def sanitize_session_for_export(session)
      {
        session_start: session.session_start.iso8601,
        session_end: session.session_end&.iso8601,
        duration_seconds: session.duration_seconds,
        page_view_count: session.page_view_count,
        entry_page: session.entry_page,
        exit_page: session.exit_page,
        device_type: session.device_type,
        converted: session.converted
      }
    end
  end
end

