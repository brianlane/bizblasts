# frozen_string_literal: true

module Public
  # JSON-only API for subdomain availability checking
  # Inherits from ApiController (ActionController::API) which has no CSRF protection
  # This eliminates CodeQL alerts while maintaining security for stateless API
  # Related: CWE-352 CSRF protection restructuring
  class SubdomainsController < ApiController
    # CSRF protection not needed: ApiController doesn't include RequestForgeryProtection module
    # JSON format enforcement handled by ApiController base class

    # POST /subdomains/check
    def check
      result = SubdomainAvailabilityService.call(params[:subdomain])
      render json: result.to_h
    rescue StandardError => e
      Rails.logger.error "[PUBLIC_SUBDOMAIN_CHECK] #{e.class}: #{e.message}"
      render json: { available: false, message: 'Unable to check availability. Please try again.' }
    end
  end
end
