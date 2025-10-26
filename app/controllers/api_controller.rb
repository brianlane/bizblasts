# frozen_string_literal: true

# Base controller for stateless JSON APIs
# Inherits from ActionController::API which has no CSRF protection by default
# This eliminates CodeQL alerts for API endpoints without weakening security
#
# Security approach:
# - ActionController::API does not include ActionController::RequestForgeryProtection module
# - APIs are designed to be stateless and use alternative authentication (API keys, tokens)
# - CSRF protection is session-based and doesn't apply to stateless APIs
# - All API controllers should inherit from this class instead of ApplicationController
#
# Related: CWE-352 CSRF protection restructuring
class ApiController < ActionController::API
  # No CSRF module included - ActionController::API is designed for stateless APIs
  # Security provided by API key authentication, not session cookies

  before_action :enforce_json_format

  private

  # Enforce JSON format for all API endpoints
  # Prevents content-type confusion attacks
  # If no format is specified, default to JSON; otherwise reject non-JSON requests
  def enforce_json_format
    # If format is not explicitly set or is wildcard, default to JSON
    if request.format.to_s == '*/*' || request.format.to_s.blank?
      request.format = :json
      return
    end

    # If a specific format is requested, it must be JSON
    unless request.format.json?
      head :not_acceptable
      return false
    end
  end
end
