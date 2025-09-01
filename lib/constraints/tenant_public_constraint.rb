# frozen_string_literal: true

# Constraint that matches any request that should be handled by tenant public routes:
# - Subdomains (excluding www and platform hosts) via SubdomainConstraint
# - Active custom domains via CustomDomainConstraint
class TenantPublicConstraint
  def self.matches?(request)
    host = request.host.to_s.downcase

    # Explicitly exclude main platform hosts from tenant public routing
    platform_hosts = %w[bizblasts.com www.bizblasts.com bizblasts.onrender.com]
    return false if platform_hosts.include?(host)

    # Reuse existing constraints for consistency
    return true if defined?(SubdomainConstraint) && SubdomainConstraint.matches?(request)
    return true if defined?(CustomDomainConstraint) && CustomDomainConstraint.matches?(request)
    false
  end
end
