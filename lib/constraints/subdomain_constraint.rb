# frozen_string_literal: true

# Constraint to check if the request has a subdomain that should be treated as a tenant request.
# This is used to route requests to tenant-specific sections.
# It matches any subdomain (except www, blank, and hosting platform domains) to allow the tenant system to handle 
# both existing and non-existent businesses appropriately.
class SubdomainConstraint
  def self.matches?(request)
    subdomain = request.subdomain
    host = request.host.downcase
    
    # Ignore www and blank subdomains/hostnames
    return false if subdomain.blank? || subdomain == 'www'
    
    # Check if this is a hosting platform request that should be treated as main domain
    return false if hosting_platform_request?(host)

    # Match any subdomain - let the tenant system decide if business exists
    # This allows both existing businesses and non-existent ones to be handled properly
    true
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