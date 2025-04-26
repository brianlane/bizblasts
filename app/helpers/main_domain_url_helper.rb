# frozen_string_literal: true

# Helper module for generating URLs related to the main application domain (no subdomain).
module MainDomainUrlHelper
  # Generates a URL for a given path on the main application domain.
  # Uses the current request's protocol and port, but removes any subdomain.
  #
  # Example:
  #   # Current request is http://test.lvh.me:3000/some/path
  #   main_domain_url_for('/dashboard') # => "http://lvh.me:3000/dashboard"
  #
  # @param path [String] The path component of the URL (e.g., '/dashboard').
  # @return [String] The full URL on the main domain.
  def main_domain_url_for(path = '/')
    # Extract base domain, handling potential ports
    base_domain = request.domain # request.domain usually excludes port
    port_string = request.port == 80 || request.port == 443 ? '' : ":#{request.port}"
    
    # Ensure path starts with a slash
    path = path.start_with?('/') ? path : "/#{path}"
    
    "#{request.protocol}#{base_domain}#{port_string}#{path}"
  end
end 