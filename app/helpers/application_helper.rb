# frozen_string_literal: true

# Global view helpers available throughout the application
# Contains commonly used formatting and presentation logic
module ApplicationHelper
  # Include CSS sanitization methods for XSS protection
  include CssSanitizer

  # Include route helpers from engines/namespaces needed globally or in test contexts
  include BusinessManager::Engine.routes.url_helpers if defined?(BusinessManager::Engine)
  # Or if it's just a namespace, not a full engine:
  include Rails.application.routes.url_helpers
  # Add specific namespace helpers if needed and the above doesn't work
  # include BusinessManager::ServicesHelper # Example, might not be needed

  # Simple helper to display boolean values with some styling
  def boolean_status_tag(status, true_text = "Active", false_text = "Inactive", options = {})
    text = status ? true_text : false_text
    
    # Default CSS classes using Tailwind
    if status
      css_class = "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800"
    else
      css_class = "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800"
    end
    
    # Allow custom classes via options
    css_class = options[:class] if options[:class].present?
    
    content_tag(:span, text, class: css_class)
  end

  def book_now_path_with_service_area(fallback_path:, service: nil)
    policy = current_tenant&.booking_policy
    return fallback_path unless policy&.service_radius_enabled?

    params = {}
    params[:service_id] = service.id if service.present?
    params[:return_to] = fallback_path
    new_service_area_check_path(params)
  end

  # Returns service name together with its variant if the booking has one.
  # Example: "Massage — Deep Tissue"
  def service_with_variant(booking)
    return '' unless booking&.service

    base = booking.service.name
    variant = booking.service_variant&.name
    variant.present? ? "#{base} — #{variant}" : base
  end

  # Returns the price for a booking, preferring the variant price when present.
  # Usage: number_to_currency(service_price(booking))
  def service_price(booking)
    return 0 unless booking && booking.respond_to?(:service)

    booking.service_variant&.price || booking.service&.price || 0
  end

  # Returns the duration (in minutes) for a booking, preferring the variant duration when present.
  # Usage: service_duration(booking)
  def service_duration(booking)
    return nil unless booking && booking.respond_to?(:service)

    booking.service_variant&.duration || booking.service&.duration
  end

  # Helper to return CSS color classes based on booking status
  def status_color(status)
    case status.to_s.downcase
    when 'pending'
      'text-yellow-600' # Or bg-yellow-100 text-yellow-800 for badge style
    when 'confirmed'
      'text-green-600'  # Or bg-green-100 text-green-800
    when 'completed'
      'text-blue-600'   # Or bg-blue-100 text-blue-800
    when 'cancelled'
      'text-red-600'    # Or bg-red-100 text-red-800
    when 'noshow'
      'text-gray-500'   # Or bg-gray-100 text-gray-800
    else
      'text-gray-700'   # Default color
    end
  end

  # Helper to generate links on the main domain (no subdomain)
  def main_domain_url_for(path = '/')
    # Extract base domain, handling potential ports
    base_domain = request.domain # request.domain usually excludes port
    port_string = request.port == 80 || request.port == 443 ? '' : ":#{request.port}"
    
    # Ensure path starts with a slash
    path = path.start_with?('/') ? path : "/#{path}"
    
    "#{request.protocol}#{base_domain}#{port_string}#{path}"
  end

  # Add this method to the ApplicationHelper module
  def settings_url_for_client
    # If we're on a subdomain, generate a URL to the main domain's settings page
    if current_tenant.present?
      protocol = request.protocol
      port = request.port != 80 ? ":#{request.port}" : ""
      "#{protocol}#{request.domain}#{port}/settings"
    else
      # We're already on the main domain
      client_settings_path
    end
  end

  # Helper method to generate full URLs for blog post featured images
  # Used for social media meta tags and other places that need absolute URLs
  def blog_post_featured_image_url(blog_post)
    if blog_post.featured_image.attached?
      # Use medium variant for social media sharing (optimal for Open Graph)
      url_for(blog_post.featured_image.variant(:medium))
    elsif blog_post.featured_image_url.present?
      blog_post.featured_image_url
    else
      nil
    end
  end

  # Safely render documentation content with explicit validation
  def render_doc_content(doc_id)
    case doc_id
    when 'business-start-guide'
      render partial: 'docs/content/business-start-guide'
    when 'legal-setup-arizona'
      render partial: 'docs/content/legal-setup-arizona'
    when 'business-growth-strategies'
      render partial: 'docs/content/business-growth-strategies'
    when 'custom-domain-faq'
      render partial: 'docs/content/custom-domain-faq'
    else
      content_tag :div, class: 'text-center py-12' do
        content_tag :p, 'Documentation not available.', class: 'text-gray-500'
      end
    end
  end

  # SEO Helper Methods
  def set_seo_meta(title: nil, description: nil, canonical: nil, robots: 'index, follow')
    content_for :title, title if title.present?
    content_for :meta_description, description if description.present?
    content_for :canonical_url, canonical if canonical.present?
    content_for :robots, robots
  end

  def noindex_page!
    content_for :robots, 'noindex, nofollow'
  end

  def index_page!
    content_for :robots, 'index, follow'
  end

  def set_canonical_url(url)
    content_for :canonical_url, url
  end

  # Current page helpers for meta tags
  def title(page_title)
    content_for(:title, page_title)
  end

  def meta_description(description)
    content_for(:meta_description, description)
  end

  def canonical_url(url)
    content_for(:canonical_url, url)
  end

  def robots(content)
    content_for(:robots, content)
  end

  # CSS sanitization helper to prevent XSS attacks in custom CSS
  def sanitize_css(css_content)
    return '' if css_content.blank?

    # Remove dangerous patterns repeatedly to prevent nested injection attacks
    # Example attack: <sc<script>ript> or ononloadload

    # Remove script tags - loop until none remain
    # Remove script tags using Rails' built-in HTML sanitizer
    # This handles malformed tags and browser quirks more reliably than regex
    css_content = sanitize(css_content, tags: [], attributes: [])

    # Remove javascript: URLs - loop until none remain
    loop do
      before = css_content
      css_content = css_content.gsub(/javascript:/i, '')
      break if before == css_content
    end

    # Remove CSS expressions - loop until none remain
    loop do
      before = css_content
      css_content = css_content.gsub(/expression\s*\(/i, '')
      break if before == css_content
    end

    # Remove behavior CSS property - loop until none remain
    loop do
      before = css_content
      css_content = css_content.gsub(/behavior\s*:/i, '')
      break if before == css_content
    end

    # Remove @import - loop until none remain
    loop do
      before = css_content
      css_content = css_content.gsub(/@import/i, '')
      break if before == css_content
    end

    # Remove vbscript: URLs - loop until none remain
    loop do
      before = css_content
      css_content = css_content.gsub(/vbscript:/i, '')
      break if before == css_content
    end

    # Remove onload event - loop until none remain
    loop do
      before = css_content
      css_content = css_content.gsub(/onload/i, '')
      break if before == css_content
    end

    # Remove onerror event - loop until none remain
    loop do
      before = css_content
      css_content = css_content.gsub(/onerror/i, '')
      break if before == css_content
    end

    # Strip HTML tags while preserving CSS
    strip_tags(css_content)
  end

  # Safely construct a URL to a business's domain
  # This method sanitizes the hostname and constructs a proper URL
  # to prevent XSS attacks via hostname manipulation
  #
  # @param business [Business] The business object
  # @param path [String] The path for the URL (default: '/')
  # @param params [Hash] Query parameters (default: {})
  # @param fragment [String] URL fragment/anchor (optional, e.g., 'section-1')
  # @return [String, nil] The constructed URL or nil if invalid
  #
  # @example
  #   safe_business_url(business, '/products', { category: 'shoes' }, 'featured')
  #   #=> "https://business.example.com/products?category=shoes#featured"
  def safe_business_url(business, path = '/', params = {}, fragment: nil)
    return nil unless business&.hostname.present?

    # Validate that hostname matches expected format
    # This provides defense-in-depth even though Business model has validations
    hostname = business.hostname.to_s.strip.downcase

    # For custom domains, ensure it's a valid domain format
    if business.host_type_custom_domain?
      unless hostname.match?(/\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9][a-z0-9-]{0,61}[a-z0-9]\z/)
        Rails.logger.warn("Invalid custom domain hostname: #{hostname}")
        return nil
      end
      host = hostname
    else
      # For subdomains, ensure it matches subdomain format
      unless hostname.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
        Rails.logger.warn("Invalid subdomain hostname: #{hostname}")
        return nil
      end
      # Construct subdomain URL
      host = "#{hostname}.#{request.domain}"
    end

    # Add port if not standard
    port_part = (request.port.present? && ![80, 443].include?(request.port.to_i)) ? ":#{request.port}" : ""

    # Construct URL with proper encoding
    protocol = request.ssl? ? "https" : "http"
    url = "#{protocol}://#{host}#{port_part}#{path}"

    # Add query parameters if provided
    if params.present?
      query_string = params.map { |k, v| "#{ERB::Util.url_encode(k.to_s)}=#{ERB::Util.url_encode(v.to_s)}" }.join('&')
      url += "?#{query_string}"
    end

    # Add fragment if provided (sanitized to prevent XSS)
    if fragment.present?
      # Sanitize fragment: only allow alphanumeric, hyphens, underscores
      # This prevents XSS attempts via fragment identifiers
      sanitized_fragment = fragment.to_s.gsub(/[^a-zA-Z0-9\-_]/, '')
      url += "##{sanitized_fragment}" if sanitized_fragment.present?
    end

    url
  end

  # Safe method to render theme CSS variables
  def render_theme_css_variables(theme)
    # CSS variables are generated by model method that only uses stored data
    theme.generate_css_variables.html_safe
  end

  # Safe method to render theme custom CSS
  def render_theme_custom_css(theme)
    return '' unless theme.custom_css.present?
    sanitize_css(theme.custom_css).html_safe
  end

  # Lazy loading image helper for performance optimization
  def lazy_image_tag(source, options = {})
    # Add lazy loading attributes for better performance
    options[:loading] ||= 'lazy'
    options[:decoding] ||= 'async'
    
    # Add a default alt text if none provided
    options[:alt] ||= ''
    
    image_tag(source, options)
  end

  # For Active Storage blobs with lazy loading
  def lazy_blob_image_tag(blob, variant_options = {}, html_options = {})
    html_options[:loading] ||= 'lazy'
    html_options[:decoding] ||= 'async'
    html_options[:alt] ||= ''
    
    if variant_options.present?
      image_tag rails_public_blob_url(blob.variant(variant_options)), html_options
    else
      image_tag rails_public_blob_url(blob), html_options
    end
  end

  # Subscription helpers
  def subscription_status_class(status)
    case status.to_s.downcase
    when 'active'
      'bg-green-100 text-green-800'
    when 'paused'
      'bg-yellow-100 text-yellow-800'
    when 'cancelled'
      'bg-red-100 text-red-800'
    when 'expired'
      'bg-gray-100 text-gray-800'
    when 'failed'
      'bg-red-100 text-red-800'
    else
      'bg-gray-100 text-gray-800'
    end
  end

  def subscription_type_icon(subscription_type)
    case subscription_type.to_s
    when 'product_subscription'
      content_tag :svg, class: "w-4 h-4", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24" do
        content_tag :path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", 
                    d: "M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"
      end
    when 'service_subscription'
      content_tag :svg, class: "w-4 h-4", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24" do
        content_tag :path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", 
                    d: "M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4"
      end
    end
  end

  # Helper to generate public page URLs for business manager preview functionality
  def public_page_url(page, business = nil)
    business ||= current_business
    
    # Build the URL for the public page using TenantHost helper
    TenantHost.url_for(business, request, "/#{page.slug}")
  end

  def format_next_billing_date(date)
    return 'N/A' unless date.present?
    
    days_until = (date - Date.current).to_i
    
    case days_until
    when 0
      "Today"
    when 1
      "Tomorrow"
    when 2..7
      "In #{days_until} days"
    else
      date.strftime('%b %d, %Y')
    end
  end

  # Selective prefetch helper for high-value links
  # Use this for links that users are very likely to click
  def prefetch_link_to(name = nil, path = nil, options = {}, &block)
    # Enable prefetch only for specific high-value routes
    high_value_routes = [
      '/dashboard',
      '/services', 
      '/products',
      '/about',
      '/contact',
      '/signup',
      '/login',
      '/calendar',
      '/booking',
      '/available-slots',
      '/staff-availability'
    ]
    
    # Check if this path should have prefetch enabled
    if high_value_routes.any? { |route| path&.include?(route) }
      options[:data] ||= {}
      options[:data][:turbo_prefetch] = true
    end
    
    if block_given?
      link_to(path, options, &block)
    else
      link_to(name, path, options)
    end
  end

  # Helper for high-traffic business pages that benefit from prefetch
  def business_prefetch_link_to(name = nil, path = nil, options = {}, &block)
    # Only enable for business-facing pages that are frequently accessed
    business_routes = [
      'services',
      'products', 
      'about',
      'contact',
      'calendar',
      'booking',
      'availability',
      'available-slots',
      'staff-availability'
    ]
    
    if business_routes.any? { |route| path&.include?(route) }
      options[:data] ||= {}
      options[:data][:turbo_prefetch] = true
    end
    
    if block_given?
      link_to(path, options, &block)
    else
      link_to(name, path, options)
    end
  end

  # Specific helper for calendar and booking links (always prefetch these slow pages)
  def calendar_link_to(name = nil, path = nil, options = {}, &block)
    # Always enable prefetch for calendar/booking related pages since they're slow to load
    options[:data] ||= {}
    options[:data][:turbo_prefetch] = true
    
    # Add helpful class for calendar links
    options[:class] = "#{options[:class]} turbo-prefetched".strip
    
    if block_given?
      link_to(path, options, &block)
    else
      link_to(name, path, options)
    end
  end

  # Format a time in the current Time.zone with given strftime pattern
  # Format a time in provided or current timezone
  def display_time(time, fmt = '%l:%M %p', zone = Time.zone)
    return '' unless time
    time.in_time_zone(zone).strftime(fmt).strip
  end

  # Convenience wrapper for records associated with a business
  # Falls back to Time.zone when business or time zone missing
  def display_time_for_business(time, business, fmt = '%l:%M %p')
    tz = business&.time_zone.presence || Time.zone
    display_time(time, fmt, tz)
  end

  # Legacy method kept for compatibility
  alias_method :display_time_legacy, :display_time

  # Determine appropriate time zone for mixed transaction objects (Order or Invoice)
  def transaction_time_zone(transaction)
    if transaction.respond_to?(:business) && transaction.business.present?
      transaction.business.time_zone.presence || Time.zone
    elsif transaction.respond_to?(:order) && transaction.order&.business.present?
      transaction.order.business.time_zone.presence || Time.zone
    elsif transaction.respond_to?(:booking) && transaction.booking&.business.present?
      transaction.booking.business.time_zone.presence || Time.zone
    else
      Time.zone
    end
  end

  def display_transaction_time(time, transaction, fmt = '%l:%M %p')
    tz = transaction_time_zone(transaction)
    display_time(time, fmt, tz)
  end

  # ---------------------------------------------------------------------------
  # Sidebar navigation – data-driven implementation
  # ---------------------------------------------------------------------------
  # Uses SidebarItems.fetch to retrieve [path, icon_svg, label, extra_svg, new_tab]
  def sidebar_item_path_and_icon(item_key)
    SidebarItems.fetch(item_key, self)
  end

  # Returns an array of exactly 5 elements for predictable destructuring in the view:
# [path, icon_svg, label, extra_svg, new_tab]
# * label and extra_svg may be nil
# * new_tab is a boolean (defaults to false)
# NOTE: Always use `current_business` helper instead of the `@current_business` ivar so that
#       the method works consistently from helpers and views.

=begin
    case item_key.to_s
    when 'dashboard'
       [business_manager_dashboard_path, '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z"/></svg>', nil, nil, false]
    when 'bookings'
       [business_manager_bookings_path, '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/></svg>', nil, nil, false]
    when 'website'
       [
         current_business&.full_url || '#',
         '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9v-9m0-9v9m0 9c-5 0-9-4-9-9s4-9 9-9"/></svg>',
         'Website',
         '<svg class="w-4 h-4 ml-auto flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"/></svg>',
         true
       ]
    when 'website_builder'
       if current_business&.standard_tier? || current_business&.premium_tier?
         [business_manager_website_pages_path, '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/></svg>', nil, nil, false]
       else
         [nil, nil, nil, nil, false]
       end
    when 'transactions'
       [business_manager_transactions_path, '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01"/></svg>', nil, nil, false]
    when 'payments'
       [business_manager_payments_path, '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z"/></svg>', nil, nil, false]
    when 'staff'
       [business_manager_staff_members_path, '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"/></svg>', nil, nil, false]
    when 'services'
       [business_manager_services_path, '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4"/></svg>', nil, nil, false]
    when 'products'
       [business_manager_products_path, '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"/></svg>', nil, nil, false]
    when 'shipping_methods'
       [business_manager_shipping_methods_path, '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/></svg>', nil, nil, false]
    when 'tax_rates'
       [business_manager_tax_rates_path, '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 7h6m0 10v-3m-3 3h.01M9 17h.01M9 14h.01M12 14h.01M15 11h.01M12 11h.01M9 11h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z"/></svg>', nil, nil, false]
    when 'customers'
       [business_manager_customers_path, '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"/></svg>', nil, nil, false]
    when 'referrals'
       [business_manager_referrals_path, '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="currentColor" viewBox="0 0 490.064 490.064"><g><g><path d="M332.682,167.764c34.8-32.7,50.7-74.7,57.6-100.7c3.9-14.6,1.6-56.9-41.5-65.6c-21.3-4.3-50.5,1.2-86,12.2c-11.6,3.6-23.8,3.6-35.4,0c-35.6-11-64.7-16.1-86-12.2c-40.9,7.4-45.4,51-41.5,65.6c6.9,26,22.8,67.9,57.6,100.6c-57.7,24.5-98.4,83.5-98.4,152.5v149.3c0,10.8,8.3,20.6,19.7,20.6h331.5c11.4,0,19.7-9.7,20.7-20.6v-149.3C431.082,251.164,390.382,192.164,332.682,167.764z M139.082,55.664c-1-3.7-0.1-11.4,7.5-12c10.9-0.8,31.7-0.8,69.2,10.8c19.2,5.9,39.4,5.9,58.6,0c37.5-11.6,58.3-12.1,69.2-10.8c10.5,1.2,8.5,8.3,7.5,12c-7.2,26.9-26.2,75.1-73.1,100.1c-1.5,0-2.9-0.1-4.4-0.1h-57c-1.5,0-2.9 0-4.4 0.1C165.282,130.764,146.282,82.564,139.082,55.664z M390.682,448.964h-291.2v-128.8c0-67.1,51.8-122.3,117.1-122.3h57c64.2,0,117.1,54.1,117.1,122.3V448.964z"/><path d="M245.082,311.464c-8.4 0-15.3-6.9-15.3-15.3s6.9-15.3 15.3-15.3c4.3 0 8.2 1.7 11.2 4.8c5.9 6.3 15.8 6.6 22.1 0.7c6.3-5.9 6.6-15.8 0.7-22.1c-5.1-5.4-11.4-9.5-18.3-11.9v-6.3c0-8.7-7-15.7-15.7-15.7s-15.7 7-15.7 15.7v6.2c-18 6.5-31 23.7-31 43.9c0 25.7 20.9 46.7 46.7 46.7c8.4 0 15.3 6.9-15.3 15.3s-6.9 15.3-15.3 15.3c-4.3 0-8.2-1.7-11.2-4.8c-5.9 6.3-15.8 6.6-22.1-0.7c-6.3-5.9-6.6-15.8-0.7 22.1c5.1 5.4 11.4 9.5 18.3 11.9v6.3c0 8.7 7 15.7 15.7 15.7s15.7-7 15.7-15.7v-6.2c18-6.5 31-23.7 31-43.9C291.782,332.364 270.782,311.464 245.082,311.464z"/></g></g></svg>', nil, nil, false]
    when 'loyalty'
       [business_manager_loyalty_index_path, '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976-2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z"/></svg>', nil, nil, false]
    when 'platform'
       [business_manager_platform_index_path, '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"/></svg>', nil, nil, false]
    when 'promotions'
       [business_manager_promotions_path, '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z"/></svg>', nil, nil, false]
    when 'customer_subscriptions'
       [business_manager_customer_subscriptions_path, '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/></svg>', nil, nil, false]
    when 'settings'
       [business_manager_settings_path, '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/></svg>', nil, nil, false]
    else
       [nil, nil, nil, nil, false]
     end
  end
=end
  end

  # Business Logo Helper Methods
  # =============================

  # Generate an img tag for business logos with proper variants and fallback
  # @param business [Business] The business object
  # @param size [Symbol] The variant size (:thumb, :medium, :large)
  # @param css_class [String] Additional CSS classes
  # @param fallback [Boolean] Whether to show fallback for businesses without logos
  # @param html_options [Hash] Additional HTML attributes
  # @return [String] HTML img tag or fallback content
  def business_logo_tag(business, size: :thumb, css_class: '', fallback: true, **html_options)
    return '' unless business.present?

    # Set default HTML options
    html_options[:alt] ||= business.name
    html_options[:class] = "#{css_class} #{html_options[:class]}".strip
    html_options[:loading] ||= 'lazy'
    html_options[:decoding] ||= 'async'

    if business.logo.attached?
      begin
        # Use the specified variant
        logo_variant = business.logo.variant(variant_options_for_size(size))

        # Build srcset for HiDPI displays
        srcset_1x = rails_public_blob_url(logo_variant)
        srcset_2x = rails_public_blob_url(business.logo.variant(variant_options_for_size(size, scale: 2)))
        html_options[:srcset] = "#{srcset_1x} 1x, #{srcset_2x} 2x"

        image_tag(srcset_1x, html_options)
      rescue => e
        Rails.logger.warn "[LOGO HELPER] Failed to generate logo for business #{business.id}: #{e.message}"
        fallback ? business_logo_fallback(business, html_options) : ''
      end
    elsif fallback
      business_logo_fallback(business, html_options)
    else
      ''
    end
  end

  # Generate a URL for business logos (useful for emails, meta tags, etc.)
  # @param business [Business] The business object
  # @param size [Symbol] The variant size (:thumb, :medium, :large)
  # @return [String, nil] Public blob URL or nil if no logo
  def business_logo_url(business, size: :large)
    return nil unless business&.logo&.attached?

    begin
      variant = business.logo.variant(variant_options_for_size(size))
      rails_public_blob_url(variant)
    rescue => e
      Rails.logger.warn "[LOGO HELPER] Failed to generate logo URL for business #{business.id}: #{e.message}"
      nil
    end
  end

  ACCENT_COLOR_PALETTES = {
    'red' => {
      base: '#ef4444',
      hover: '#f87171',
      text: '#fca5a5',
      border: '#f87171',
      shadow: 'rgba(239, 68, 68, 0.45)',
      overlay: 'rgba(239, 68, 68, 0.55)'
    },
    'orange' => {
      base: '#f97316',
      hover: '#fb923c',
      text: '#fdba74',
      border: '#fb923c',
      shadow: 'rgba(249, 115, 22, 0.45)',
      overlay: 'rgba(249, 115, 22, 0.55)'
    },
    'amber' => {
      base: '#f59e0b',
      hover: '#fbbf24',
      text: '#fcd34d',
      border: '#fbbf24',
      shadow: 'rgba(245, 158, 11, 0.45)',
      overlay: 'rgba(245, 158, 11, 0.55)'
    },
    'emerald' => {
      base: '#10b981',
      hover: '#34d399',
      text: '#6ee7b7',
      border: '#34d399',
      shadow: 'rgba(16, 185, 129, 0.45)',
      overlay: 'rgba(16, 185, 129, 0.55)'
    },
    'sky' => {
      base: '#0ea5e9',
      hover: '#38bdf8',
      text: '#7dd3fc',
      border: '#38bdf8',
      shadow: 'rgba(14, 165, 233, 0.45)',
      overlay: 'rgba(14, 165, 233, 0.55)'
    },
    'violet' => {
      base: '#8b5cf6',
      hover: '#a855f7',
      text: '#c4b5fd',
      border: '#a855f7',
      shadow: 'rgba(139, 92, 246, 0.45)',
      overlay: 'rgba(139, 92, 246, 0.55)'
    }
  }.freeze

  def accent_palette_for(color)
    ACCENT_COLOR_PALETTES[color] || ACCENT_COLOR_PALETTES['red']
  end

  def accent_palette_style(color)
    palette = accent_palette_for(color)
    [
      "--accent-base: #{palette[:base]}",
      "--accent-hover: #{palette[:hover]}",
      "--accent-text: #{palette[:text]}",
      "--accent-border: #{palette[:border]}",
      "--accent-shadow: #{palette[:shadow]}",
      "--accent-overlay: #{palette[:overlay]}"
    ].join('; ')
  end

  private

  # Get variant options for different sizes
  # @param size [Symbol] The variant size
  # @param scale [Integer] Scale factor for HiDPI (1 or 2)
  # @return [Hash] Variant options for Active Storage
  def variant_options_for_size(size, scale: 1)
    base_sizes = {
      thumb: [120, 120],
      medium: [300, 300],
      large: [600, 600]
    }

    width, height = base_sizes[size] || base_sizes[:thumb]
    scaled_width = width * scale
    scaled_height = height * scale

    {
      resize_to_limit: [scaled_width, scaled_height],
      quality: scale == 1 ? 85 : 80 # Slightly lower quality for 2x to reduce file size
    }
  end

  # Generate fallback content for businesses without logos
  # @param business [Business] The business object
  # @param html_options [Hash] HTML attributes
  # @return [String] HTML content for fallback
  def business_logo_fallback(business, html_options = {})
    return '' unless business.present?

    # Handle nil or blank business names gracefully
    business_name = business.name.to_s.strip
    business_name = "Business" if business_name.blank?

    initials = business_name.split.map(&:first).join.upcase[0..1]

    # Generate a consistent background color based on business name
    color_hash = business_name.sum % 8
    bg_colors = %w[
      bg-blue-500 bg-green-500 bg-purple-500 bg-pink-500
      bg-indigo-500 bg-red-500 bg-yellow-500 bg-gray-500
    ]
    bg_color = bg_colors[color_hash]

    # Extract size from class to determine dimensions
    size_class = html_options[:class]&.match(/[hw]-(\d+)/)&.captures&.first
    size = size_class ? "#{size_class.to_i * 0.25}rem" : '3rem'

    content_tag(:div,
      content_tag(:span, initials, class: 'text-white font-semibold text-sm'),
      class: "#{bg_color} rounded-full flex items-center justify-center text-white #{html_options[:class]}",
      style: "width: #{size}; height: #{size}; min-width: #{size}; min-height: #{size}",
      title: business.name
    )
  end

