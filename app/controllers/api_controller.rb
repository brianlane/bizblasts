# frozen_string_literal: true

# Base controller for stateless JSON APIs
# Inherits from ActionController::API which has no CSRF protection by default.
# Security model relies on API keys or other token-based auth instead of sessions.
# Related: CWE-352 CSRF protection restructuring.
class ApiController < ActionController::API
  # No CSRF module included - ActionController::API is designed for stateless APIs.
  # Security provided by API key authentication or signature verification, not session cookies.

  before_action :enforce_json_format

  private

  def enforce_json_format
    return if request.format.json?

    accept_header = request.headers['Accept']

    if params[:format].blank? && (accept_header.blank? || accept_header == '*/*' || accept_header.to_s.include?('text/html'))
      request.format = :json
      return
    end

    head :not_acceptable
  end
end
