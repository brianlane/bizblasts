# frozen_string_literal: true

# CORS configuration for analytics API
# Allows tracking requests from custom domains while maintaining security

# Only load CORS if rack-cors gem is available
# This prevents boot failures if the gem isn't installed
if defined?(Rack::Cors)
  Rails.application.config.middleware.insert_before 0, Rack::Cors do
    # Analytics tracking endpoint needs to accept requests from any tenant domain
    allow do
      # Allow requests from any subdomain or custom domain
      # This is necessary for analytics tracking across different business domains
      origins do |source, _env|
        next true if source.nil? || source.empty?
        
        # Always allow requests from our platform domains
        next true if source.end_with?('.lvh.me') # Development
        next true if source.end_with?('.bizblasts.com') # Production
        next true if source == 'lvh.me' || source == 'bizblasts.com'

        # For custom domains, verify they belong to a business
        # This prevents abuse while allowing legitimate tracking
        begin
          host = URI.parse(source).host rescue source
          business = Business.find_by(hostname: host) if defined?(Business) && Business.table_exists?
          business.present?
        rescue StandardError => e
          Rails.logger.warn "[CORS] Error checking origin #{source}: #{e.message}"
          false
        end
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
      origins(/\.lvh\.me$/, /\.bizblasts\.com$/, 'lvh.me', 'bizblasts.com')

      resource '/api/v1/*',
               headers: :any,
               methods: [:get, :post, :put, :patch, :delete, :options],
               credentials: true,
               max_age: 600
    end
  end
else
  Rails.logger.warn "[CORS] rack-cors gem not available, CORS middleware not loaded"
end
