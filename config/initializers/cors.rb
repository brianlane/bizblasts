# frozen_string_literal: true

# CORS configuration for analytics API
# Allows tracking requests from custom domains while maintaining security

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  # Analytics tracking endpoint needs to accept requests from any tenant domain
  allow do
    # Allow requests from any subdomain or custom domain
    # This is necessary for analytics tracking across different business domains
    origins do |source, env|
      # Always allow requests from our platform domains
      return true if source.end_with?('.lvh.me') # Development
      return true if source.end_with?('.bizblasts.com') # Production

      # For custom domains, verify they belong to a business
      # This prevents abuse while allowing legitimate tracking
      business = Business.find_by(hostname: URI.parse(source).host)
      business.present?

    rescue URI::InvalidURIError
      false
    end

    # Only allow analytics endpoint
    resource '/api/v1/analytics/*',
             headers: :any,
             methods: [:post, :options],
             credentials: false, # No cookies/credentials needed
             max_age: 600 # Cache preflight for 10 minutes
  end

  # Separate rule for other API endpoints (stricter)
  allow do
    # Only platform domains for other APIs
    origins(/\.lvh\.me$/, /\.bizblasts\.com$/)

    resource '/api/v1/*',
             headers: :any,
             methods: [:get, :post, :put, :patch, :delete, :options],
             credentials: true,
             max_age: 600
  end
end
