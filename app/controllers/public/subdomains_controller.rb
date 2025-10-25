# frozen_string_literal: true

module Public
  class SubdomainsController < BaseController
    # SECURITY: null_session is LEGITIMATE pattern for JSON-only validation endpoint
    # - This is a JSON-only API endpoint for subdomain availability checking
    # - Uses null_session pattern (Rails recommended for APIs) instead of skipping CSRF
    # - No state changes - read-only validation (see line 11)
    # - ensure_json_request enforces JSON format (see line 20)
    # Related security: CWE-352 (CSRF) mitigation via null_session for stateless API
    protect_from_forgery with: :null_session
    skip_before_action :authenticate_user!, only: :check
    before_action :ensure_json_request

    # POST /subdomains/check
    def check
      result = SubdomainAvailabilityService.call(params[:subdomain])
      render json: result.to_h
    rescue StandardError => e
      Rails.logger.error "[PUBLIC_SUBDOMAIN_CHECK] #{e.class}: #{e.message}"
      render json: { available: false, message: 'Unable to check availability. Please try again.' }
    end

    private

    def ensure_json_request
      return if request.format.json?

      head :unsupported_media_type
    end
  end
end
