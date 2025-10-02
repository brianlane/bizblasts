# frozen_string_literal: true

# Constraint to check if the request is from a business domain (subdomain or custom domain).
# This is used specifically for business manager routes that should be available on both
# subdomains and active custom domains.
class BusinessDomainConstraint
  def self.matches?(request)
    subdomain = request.subdomain
    host = request.host.downcase

    # Check if this is a hosting platform request that should be treated as main domain
    return false if hosting_platform_request?(host)

    # First check for subdomain (original SubdomainConstraint logic)
    if subdomain.present? && subdomain != 'www'
      # Match any subdomain - let the tenant system decide if business exists
      # This allows both existing businesses and non-existent ones to be handled properly
      return true
    end

    # Second check for active custom domains
    # Use the CustomDomainConstraint logic to check if this is a valid custom domain
    CustomDomainConstraint.matches?(request)
  end

  private

  # Check if the request is from a hosting platform that should be treated as main domain
  def self.hosting_platform_request?(host)
    hosting_patterns = [
      '.onrender.com',     # Render
      '.netlify.app',      # Netlify
      '.vercel.app',       # Vercel
      '.herokuapp.com',    # Heroku
      '.railway.app',      # Railway
      '.fly.dev'           # Fly.io
    ]

    hosting_patterns.any? { |pattern| host.include?(pattern) }
  end
end