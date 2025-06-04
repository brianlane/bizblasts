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

  # ... existing helper methods ...
end
