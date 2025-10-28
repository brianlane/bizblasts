# frozen_string_literal: true

module Public
  # JSON-only API for subdomain availability checking
  # Inherits from ApiController (ActionController::API) which has no CSRF protection
  # This eliminates CodeQL alerts while maintaining security for stateless API
  # Related: CWE-352 CSRF protection restructuring
  class SubdomainsController < ApiController
    # SECURITY: CSRF protection not needed (ApiController uses null_session pattern)
    # - ApiController doesn't include RequestForgeryProtection module
    # - Stateless API with no session cookies
    # Related: CWE-352 CSRF protection restructuring

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
