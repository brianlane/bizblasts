# frozen_string_literal: true

# Base controller for stateless JSON APIs
# Inherits from ActionController::API which has no CSRF protection by default.
# Security model relies on API keys or other token-based auth instead of sessions.
# Related: CWE-352 CSRF protection restructuring.
class ApiController < ActionController::API
  # No CSRF module included - ActionController::API is designed for stateless APIs.
  # Security provided by API key authentication or signature verification, not session cookies.
end
