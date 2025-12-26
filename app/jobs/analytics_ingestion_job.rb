# frozen_string_literal: true

# Background job for processing analytics events
# Handles page views, click events, and session management
class AnalyticsIngestionJob < ApplicationJob
  queue_as :analytics

  # Process a batch of analytics events
  # @param business_id [Integer, nil] The business ID (may be nil if not determined)
  # @param events [Array<Hash>] Array of event data
  # @param request_metadata [Hash] Request metadata (IP, user agent, host)
  def perform(business_id:, events:, request_metadata: {})
    return if events.blank?
    
    # Find or validate business
    business = business_id.present? ? Business.find_by(id: business_id) : nil
    
    # Process each event
    events.each do |event|
      process_event(event, business, request_metadata)
    rescue StandardError => e
      Rails.logger.error "[AnalyticsIngestion] Failed to process event: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end
  end

  private

  def process_event(event, business, request_metadata)
    # Try to find business from event if not provided
    business ||= find_business_from_event(event)
    return unless business.present?
    
    # Set tenant context
    ActsAsTenant.with_tenant(business) do
      case event[:type]
      when 'page_view'
        process_page_view(event, business, request_metadata)
      when 'page_view_update'
        process_page_view_update(event, business)
      when 'click'
        process_click_event(event, business)
      when 'conversion'
        process_conversion(event, business)
      else
        Rails.logger.warn "[AnalyticsIngestion] Unknown event type: #{event[:type]}"
      end
    end
  end

  def find_business_from_event(event)
    business_id = event[:business_id]
    return nil unless business_id.present? && business_id > 0
    
    Business.find_by(id: business_id)
  end

  def process_page_view(event, business, request_metadata)
    data = event[:data] || {}
    session_id = event[:session_id]
    visitor_fingerprint = event[:visitor_fingerprint]
    
    return unless session_id.present? && visitor_fingerprint.present?
    
    # Ensure visitor session exists
    session = find_or_create_session(business, session_id, visitor_fingerprint, data, request_metadata)
    
    # Determine if this is an entry page (first page view in session)
    is_entry = session.page_view_count.to_i == 0
    
    # Create page view record
    page_view = business.page_views.create!(
      visitor_fingerprint: visitor_fingerprint,
      session_id: session_id,
      page_path: data['page_path'],
      page_type: data['page_type'],
      page_title: data['page_title'],
      referrer_url: data['referrer_url'],
      referrer_domain: data['referrer_domain'],
      utm_source: data['utm_source'],
      utm_medium: data['utm_medium'],
      utm_campaign: data['utm_campaign'],
      utm_term: data['utm_term'],
      utm_content: data['utm_content'],
      device_type: data['device_type'],
      browser: data['browser'],
      browser_version: data['browser_version'],
      os: data['os'],
      screen_resolution: data['screen_resolution'],
      country: extract_country(request_metadata),
      is_entry_page: is_entry
    )
    
    # Update session entry page if this is the first view
    if is_entry
      session.update!(entry_page: data['page_path'])
    end
    
    # Increment session page view count
    session.record_page_view!
    
    # Link to Page model if applicable
    link_to_page(page_view, business, data['page_path'])
  end

  def process_page_view_update(event, business)
    data = event[:data] || {}
    session_id = event[:session_id]
    
    return unless session_id.present?
    
    # Find the most recent page view for this session and path
    page_view = business.page_views
      .where(session_id: session_id, page_path: data['page_path'])
      .order(created_at: :desc)
      .first
    
    return unless page_view.present?
    
    # Update with engagement metrics
    page_view.update!(
      time_on_page: data['time_on_page'].to_i,
      scroll_depth: data['scroll_depth'].to_i,
      is_exit_page: data['is_exit_page'] == true
    )
    
    # Update session exit page
    if data['is_exit_page']
      session = business.visitor_sessions.find_by(session_id: session_id)
      session&.update!(exit_page: data['page_path'])
    end
  end

  def process_click_event(event, business)
    data = event[:data] || {}
    session_id = event[:session_id]
    visitor_fingerprint = event[:visitor_fingerprint]
    
    return unless session_id.present? && visitor_fingerprint.present?
    
    # Create click event record
    click_event = business.click_events.create!(
      visitor_fingerprint: visitor_fingerprint,
      session_id: session_id,
      element_type: data['element_type'] || 'other',
      element_identifier: data['element_identifier'],
      element_text: data['element_text']&.first(255),
      element_class: data['element_class']&.first(200),
      element_href: data['element_href']&.first(2000),
      page_path: data['page_path'],
      page_title: data['page_title'],
      category: data['category'] || 'other',
      action: data['action'] || 'click',
      label: data['label'],
      target_type: data['target_type'],
      target_id: data['target_id']&.to_i,
      conversion_value: data['conversion_value']&.to_f,
      click_x: data['click_x']&.to_i,
      click_y: data['click_y']&.to_i,
      viewport_width: data['viewport_width']&.to_i,
      viewport_height: data['viewport_height']&.to_i
    )
    
    # Update session click count
    session = business.visitor_sessions.find_by(session_id: session_id)
    session&.record_click!
    
    # Check for conversion signals
    check_conversion_signal(click_event, session)
  end

  def process_conversion(event, business)
    data = event[:data] || {}
    session_id = event[:session_id]
    
    return unless session_id.present?
    
    session = business.visitor_sessions.find_by(session_id: session_id)
    return unless session.present?
    
    # Mark session as converted
    session.mark_converted!(
      data['conversion_type'],
      data['conversion_value']&.to_f
    )
    
    # Also create a click event record for the conversion
    business.click_events.create!(
      visitor_fingerprint: event[:visitor_fingerprint],
      session_id: session_id,
      element_type: 'conversion',
      page_path: data['page_path'],
      category: data['conversion_type']&.split('_')&.first || 'other',
      action: 'convert',
      is_conversion: true,
      conversion_type: data['conversion_type'],
      conversion_value: data['conversion_value']&.to_f
    )
  end

  def find_or_create_session(business, session_id, visitor_fingerprint, data, request_metadata)
    # First attempt: try to find existing session
    session = business.visitor_sessions.find_by(session_id: session_id)
    return session if session.present?

    # Check if this is a returning visitor
    previous_sessions = business.visitor_sessions
      .where(visitor_fingerprint: visitor_fingerprint)
      .count

    # Create session with race condition handling
    # If another worker created the session between our find and create,
    # we'll get a RecordNotUnique exception and retry the find
    begin
      business.visitor_sessions.create!(
        session_id: session_id,
        visitor_fingerprint: visitor_fingerprint,
        session_start: Time.current,
        device_type: data['device_type'],
        browser: data['browser'],
        os: data['os'],
        country: extract_country(request_metadata),
        first_referrer_url: data['referrer_url'],
        first_referrer_domain: data['referrer_domain'],
        utm_source: data['utm_source'],
        utm_medium: data['utm_medium'],
        utm_campaign: data['utm_campaign'],
        is_returning_visitor: previous_sessions > 0,
        previous_session_count: previous_sessions
      )
    rescue ActiveRecord::RecordNotUnique
      # Another worker created the session first - find and return it
      business.visitor_sessions.find_by!(session_id: session_id)
    end
  end

  def link_to_page(page_view, business, page_path)
    return unless page_path.present?
    
    # Try to find a matching Page record
    slug = page_path.gsub(/^\//, '').presence || 'home'
    page = business.pages.find_by(slug: slug)
    
    if page.present?
      page_view.update!(page_id: page.id)
    end
  end

  def extract_country(request_metadata)
    # In production, you could use a GeoIP service
    # For now, default to nil (could be enhanced later)
    nil
  end

  def check_conversion_signal(click_event, session)
    return unless session.present?
    
    # Check if this click indicates a conversion started
    conversion_categories = %w[booking estimate]
    conversion_actions = %w[book submit add_to_cart]
    
    if click_event.category.in?(conversion_categories) && 
       click_event.action.in?(conversion_actions)
      # Mark as potential conversion started
      click_event.update!(
        is_conversion: true,
        conversion_type: "#{click_event.category}_started"
      )
    end
  end
end

