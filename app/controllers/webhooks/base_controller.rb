# frozen_string_literal: true

module Webhooks
  # Base controller for webhook endpoints
  #
  # Inherits from ActionController::API instead of ApplicationController because:
  # - Webhooks are server-to-server callbacks, not browser requests
  # - They cannot include CSRF tokens (no browser session)
  # - They use alternative authentication (signatures, IP allowlists, secrets)
  # - ActionController::API is the Rails-idiomatic base for non-browser endpoints
  #
  # Each webhook controller MUST implement its own authentication:
  # - Signature verification (HMAC)
  # - IP allowlist validation
  # - Shared secret verification
  class BaseController < ActionController::API
    # Include only the modules we need for webhook processing
    include ActionController::MimeResponds

    # Logging for debugging webhook issues
    before_action :log_webhook_request

    private

    def log_webhook_request
      Rails.logger.info "[Webhooks] #{controller_name}##{action_name} from #{request.remote_ip}"
    end
  end
end
