# frozen_string_literal: true

# Helper module for generating URLs related to tenants (Businesses)
module TenantUrlHelper
  # Generates the root URL for a given business tenant based on its hostname.
  # Uses the current request's protocol and port.
  # Assumes the business hostname is the subdomain.
  #
  # Example:
  #   business = Business.find_by(hostname: 'acme')
  #   tenant_url(business) # => "http://acme.lvh.me:3000"
  #
  # @param business [Business] The business tenant object.
  # @return [String, nil] The full root URL for the tenant, or nil if business is nil.
  def tenant_url(business)
    return nil unless business&.hostname

    # Use request.host to get the base domain (e.g., lvh.me)
    # Remove existing subdomain if present to construct the base domain.
    # This handles cases where the helper might be called from a subdomain context.
    # For simplicity, assumes standard ports (80, 443) are omitted by request.host
    # unless explicitly included (like in development with :3000).
    base_domain = request.host.split('.').last(2).join('.') # Simple extraction
    port_string = request.port == 80 || request.port == 443 ? '' : ":#{request.port}"

    "#{request.protocol}#{business.hostname}.#{base_domain}#{port_string}"
  end
end 