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
    # Use TenantHost helper for consistent main domain URL generation
    # Create a mock business with no tenant setup to get main domain behavior
    TenantHost.main_domain_url_for(request, path)
  end
end 