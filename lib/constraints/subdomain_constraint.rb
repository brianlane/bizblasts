# frozen_string_literal: true

# Constraint to check if the request hostname matches a known Business hostname.
# This is used to route requests to tenant-specific sections.
class SubdomainConstraint
  def self.matches?(request)
    subdomain = request.subdomain
    Rails.logger.debug "[SubdomainConstraint] Checking request subdomain: #{subdomain.inspect}"
    
    # Ignore www and blank subdomains/hostnames
    return false if subdomain.blank? || subdomain == 'www'

    # Check if a Business exists with the requested hostname (case-insensitive)
    # Use unscoped to ensure we check across all tenants initially
    # This avoids issues if ActsAsTenant is already set incorrectly
    exists = ActsAsTenant.without_tenant do
      # Use LOWER() for case-insensitive comparison on hostname or subdomain column
      Business.where(host_type: 'subdomain')
             .where("LOWER(hostname) = ? OR LOWER(subdomain) = ?", subdomain.downcase, subdomain.downcase)
             .exists?
    end
    Rails.logger.debug "[SubdomainConstraint] Match result for hostname '#{subdomain}': #{exists}"
    exists
  end
end 