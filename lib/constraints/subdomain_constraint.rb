# frozen_string_literal: true

# Constraint to check if the request has a subdomain that should be treated as a tenant request.
# This is used to route requests to tenant-specific sections.
# It matches any subdomain (except www and blank) to allow the tenant system to handle 
# both existing and non-existent businesses appropriately.
class SubdomainConstraint
  def self.matches?(request)
    subdomain = request.subdomain
    Rails.logger.debug "[SubdomainConstraint] Checking request subdomain: #{subdomain.inspect}"
    
    # Ignore www and blank subdomains/hostnames
    return false if subdomain.blank? || subdomain == 'www'

    # Match any subdomain - let the tenant system decide if business exists
    # This allows both existing businesses and non-existent ones to be handled properly
    Rails.logger.debug "[SubdomainConstraint] Matching subdomain '#{subdomain}' for tenant routing"
    true
  end
end 