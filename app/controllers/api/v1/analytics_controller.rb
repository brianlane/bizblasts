# frozen_string_literal: true

module Api
  module V1
    # Analytics tracking endpoint for page views and click events
    # Inherits from ApiController (ActionController::API) for stateless JSON API
    class AnalyticsController < ApiController
      # No CSRF needed - stateless API with anonymous tracking
      before_action :set_business_from_host, only: [:track]
      before_action :check_privacy_settings, only: [:track]
      
      # Rate limiting - 100 requests per minute per IP
      MAX_REQUESTS_PER_MINUTE = 100
      
      # POST /api/v1/analytics/track
      def track
        # Rate limiting check
        if rate_limited?
          render json: { error: 'Rate limit exceeded' }, status: :too_many_requests
          return
        end
        
        # Privacy check - skip if tracking should be disabled
        if @skip_tracking
          render json: { status: 'skipped', reason: 'privacy' }, status: :ok
          return
        end
        
        # Validate events parameter
        unless params[:events].is_a?(Array)
          render json: { error: 'Events must be an array' }, status: :bad_request
          return
        end
        
        # Process events asynchronously
        events_data = params[:events].map do |event|
          sanitize_event(event)
        end.compact
        
        if events_data.any?
          # Queue for background processing
          AnalyticsIngestionJob.perform_later(
            business_id: @business&.id,
            events: events_data,
            request_metadata: request_metadata
          )
        end
        
        render json: { status: 'queued', count: events_data.size }, status: :accepted
      end
      
      private
      
      def set_business_from_host
        @business = find_business_from_request
        
        # Allow tracking even if business not found - will be discarded in job
        # This prevents errors on misconfigured pages
      end
      
      def find_business_from_request
        host = request.host.to_s.downcase
        
        # Try to find business by subdomain or hostname
        if host.include?('lvh.me') || host.include?('bizblasts.com')
          # Extract subdomain
          subdomain = host.split('.').first
          return nil if subdomain.in?(%w[www api admin])
          
          Business.find_by(subdomain: subdomain) || Business.find_by(hostname: subdomain)
        else
          # Custom domain
          Business.find_by(hostname: host)
        end
      end
      
      def rate_limited?
        cache_key = "analytics_rate_limit:#{request.remote_ip}"
        current_count = Rails.cache.read(cache_key).to_i
        
        if current_count >= MAX_REQUESTS_PER_MINUTE
          true
        else
          Rails.cache.write(cache_key, current_count + 1, expires_in: 1.minute)
          false
        end
      end
      
      def sanitize_event(event)
        return nil unless event.is_a?(Hash) || event.is_a?(ActionController::Parameters)
        
        event_params = event.to_unsafe_h if event.respond_to?(:to_unsafe_h)
        event_params ||= event.to_h
        
        {
          type: event_params['type']&.to_s&.strip,
          timestamp: event_params['timestamp']&.to_s,
          session_id: event_params['session_id']&.to_s&.strip&.first(100),
          visitor_fingerprint: event_params['visitor_fingerprint']&.to_s&.strip&.first(32),
          business_id: event_params['business_id']&.to_i,
          data: sanitize_event_data(event_params['data'])
        }.compact
      end
      
      def sanitize_event_data(data)
        return {} unless data.is_a?(Hash) || data.is_a?(ActionController::Parameters)
        
        data_hash = data.to_unsafe_h if data.respond_to?(:to_unsafe_h)
        data_hash ||= data.to_h
        
        # Whitelist allowed fields and sanitize
        allowed_fields = %w[
          page_path page_title page_type referrer_url referrer_domain
          utm_source utm_medium utm_campaign utm_term utm_content
          device_type browser browser_version os os_version screen_resolution
          viewport_width viewport_height time_on_page scroll_depth
          is_entry_page is_exit_page is_bounce
          element_type element_identifier element_text element_class element_href
          category action label target_type target_id conversion_value
          click_x click_y conversion_type
        ]
        
        sanitized = {}
        allowed_fields.each do |field|
          value = data_hash[field]
          next if value.nil?
          
          sanitized[field] = case field
          when 'page_path', 'page_title', 'page_type', 'referrer_domain',
               'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
               'device_type', 'browser', 'browser_version', 'os', 'os_version',
               'screen_resolution', 'element_type', 'element_identifier',
               'category', 'action', 'label', 'target_type', 'conversion_type'
            value.to_s.strip.first(255)
          when 'element_text', 'element_class'
            value.to_s.strip.first(200)
          when 'referrer_url', 'element_href'
            value.to_s.strip.first(2000)
          when 'viewport_width', 'viewport_height', 'time_on_page', 'scroll_depth',
               'click_x', 'click_y', 'target_id'
            value.to_i
          when 'conversion_value'
            value.to_f
          when 'is_entry_page', 'is_exit_page', 'is_bounce'
            value == true || value == 'true'
          else
            value.to_s.first(255)
          end
        end
        
        sanitized
      end
      
      def request_metadata
        {
          ip_address: anonymize_ip(request.remote_ip),
          user_agent: request.user_agent&.first(500),
          host: request.host
        }
      end
      
      def anonymize_ip(ip)
        @privacy_service.anonymize_ip(ip)
      end
      
      def check_privacy_settings
        @privacy_service = ::Analytics::PrivacyService.new(@business)
        @skip_tracking = @privacy_service.should_disable_tracking?(request)
      end
    end
  end
end

