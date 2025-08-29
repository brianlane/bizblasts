# frozen_string_literal: true

module Public
  class SubdomainsController < BaseController
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
