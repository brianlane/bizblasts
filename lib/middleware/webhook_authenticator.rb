# frozen_string_literal: true

module Middleware
  # Webhook signature verification middleware
  #
  # This middleware verifies webhook signatures BEFORE requests reach controllers,
  # providing defense-in-depth security for external webhook endpoints.
  #
  # Supports:
  # - Stripe webhook signature verification (HMAC-SHA256)
  # - Twilio webhook signature verification (X-Twilio-Signature)
  #
  # Security benefits:
  # - Controllers can enable full CSRF protection (no skips needed)
  # - Signature verification happens at middleware layer (earlier in request cycle)
  # - Tenant context is not modified (maintains isolation)
  # - Failed verification returns 401 before controller processing
  #
  # Related: CWE-352 CSRF protection restructuring
  class WebhookAuthenticator
    STRIPE_PATHS = %r{
      ^/webhooks/stripe$ |
      ^/manage/settings/subscriptions/webhook$
    }x

    TWILIO_PATHS = %r{
      ^/webhooks/twilio$ |
      ^/webhooks/plivo$
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
      STRIPE_PATHS.match?(path) || TWILIO_PATHS.match?(path)
    end

    def verify_signature(request)
      if STRIPE_PATHS.match?(request.path)
        verify_stripe_signature(request)
      elsif TWILIO_PATHS.match?(request.path)
        verify_twilio_signature(request)
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

    def verify_twilio_signature(request)
      auth_token = ENV['TWILIO_AUTH_TOKEN']
      return false if auth_token.blank?

      begin
        validator = Twilio::Security::RequestValidator.new(auth_token)

        # Construct full URL including query string
        url = "#{request.scheme}://#{request.host_with_port}#{request.fullpath}"

        # Get POST parameters
        params = request.request_parameters

        # Get signature from header
        signature = request.env['HTTP_X_TWILIO_SIGNATURE']
        return false if signature.blank?

        # Validate signature
        valid = validator.validate(url, params, signature)

        unless valid
          Rails.logger.warn "[WebhookAuth] Twilio signature validation failed for URL: #{url}"
        end

        valid
      rescue => e
        Rails.logger.error "[WebhookAuth] Twilio signature verification error: #{e.class.name} - #{e.message}"
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
