# frozen_string_literal: true

# Global view helpers available throughout the application
# Contains commonly used formatting and presentation logic
module ApplicationHelper
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

  # ... existing helper methods ...
end
