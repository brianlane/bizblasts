# frozen_string_literal: true

module Middleware
  # Webhook signature verification middleware
  #
  # This middleware verifies Stripe webhook signatures BEFORE requests reach controllers,
  # providing defense-in-depth security for external webhook endpoints.
  #
  # Supports:
  # - Stripe webhook signature verification (HMAC-SHA256)
  #
  # Security benefits:
  # - Controllers can enable full CSRF protection (no skips needed)
  # - Signature verification happens at middleware layer (earlier in request cycle)
  # - Tenant context is not modified (maintains isolation)
  # - Failed verification returns 401 before controller processing
  #
  # Note: Other webhook providers (e.g., Twilio) use ActionController::API
  # and verify signatures in their controllers directly.
  #
  # Related: CWE-352 CSRF protection restructuring
  class WebhookAuthenticator
    STRIPE_PATHS = %r{
      ^/webhooks/stripe$ |
      ^/manage/settings/subscriptions/webhook$
    }x

    def initialize(app)
      @app = app
    end

    def call(env)
      request = ActionDispatch::Request.new(env)

      if webhook_path?(request.path)
        Rails.logger.info "[WebhookAuth] Processing webhook request to #{request.path}"

        unless verify_signature(request)
          Rails.logger.warn "[WebhookAuth] Signature verification failed for #{request.path} from IP #{request.remote_ip}"
          return unauthorized_response(request.path)
        end

        Rails.logger.info "[WebhookAuth] Signature verified successfully for #{request.path}"
      end

      @app.call(env)
    end

    private

    def webhook_path?(path)
      STRIPE_PATHS.match?(path)
    end

    def verify_signature(request)
      if STRIPE_PATHS.match?(request.path)
        verify_stripe_signature(request)
      else
        false
      end
    end

    def verify_stripe_signature(request)
      payload = request.body.read
      request.body.rewind # Important: rewind so controller can read again
      sig_header = request.env['HTTP_STRIPE_SIGNATURE']

      return false if sig_header.blank?

      endpoint_secret = Rails.application.credentials.dig(:stripe, :webhook_secret) ||
                       ENV['STRIPE_WEBHOOK_SECRET']

      return false if endpoint_secret.blank?

      begin
        Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
        true
      rescue JSON::ParserError => e
        Rails.logger.warn "[WebhookAuth] Stripe webhook JSON parse error: #{e.message}"
        false
      rescue Stripe::SignatureVerificationError => e
        Rails.logger.warn "[WebhookAuth] Stripe signature verification failed: #{e.message}"
        false
      end
    end

    def unauthorized_response(path)
      Rails.logger.warn "[WebhookAuth] Returning 401 Unauthorized for #{path}"
      [
        401,
        {
          'Content-Type' => 'application/json',
          'X-Webhook-Error' => 'Invalid signature'
        },
        ['{"error":"Unauthorized webhook request - invalid signature"}']
      ]
    end
  end
end
