# frozen_string_literal: true

module Webhooks
  # Handles incoming webhooks from email marketing platforms (Mailchimp, Constant Contact)
  #
  # Inherits from Webhooks::BaseController (ActionController::API) which does not include
  # CSRF protection - this is correct because webhooks are server-to-server callbacks
  # that cannot include CSRF tokens.
  #
  # Authentication is handled via:
  # - Mailchimp: IP allowlist + optional webhook secret (verify_mailchimp_request)
  # - Constant Contact: HMAC signature verification (verify_constant_contact_signature)
  class EmailMarketingController < BaseController
    # Mailchimp sends a GET request to verify the webhook URL
    # GET /webhooks/email-marketing/mailchimp
    def mailchimp_verify
      render plain: 'OK', status: :ok
    end

    # POST /webhooks/email-marketing/mailchimp
    def mailchimp
      Rails.logger.info "[Webhooks::EmailMarketing] Received Mailchimp webhook"

      # Verify webhook source (IP allowlist or webhook secret if configured)
      unless verify_mailchimp_request
        Rails.logger.warn "[Webhooks::EmailMarketing] Invalid Mailchimp webhook - unauthorized source IP: #{request.remote_ip}"
        head :unauthorized
        return
      end

      # Mailchimp webhooks are form-encoded, not JSON
      webhook_type = params['type']
      # Use to_unsafe_h to avoid ActionController::UnfilteredParameters error
      # when accessing nested params that haven't been permitted.
      # This is safe because we're processing webhook data, not user input for mass assignment.
      raw_params = params.to_unsafe_h.except('controller', 'action')
      webhook_data = raw_params['data'] || raw_params
      list_id = webhook_data['list_id'] || raw_params.dig('data', 'list_id')

      # Find the connection for this list
      connection = find_mailchimp_connection(list_id)

      unless connection
        Rails.logger.warn "[Webhooks::EmailMarketing] No Mailchimp connection found for list #{list_id}"
        head :ok
        return
      end

      # Process the webhook asynchronously
      # webhook_data is already a Hash from to_unsafe_h, no need to call .to_h
      EmailMarketing::ProcessWebhookJob.perform_later(
        'mailchimp',
        connection.id,
        {
          type: webhook_type,
          data: webhook_data,
          received_at: Time.current.iso8601
        }
      )

      head :ok
    rescue StandardError => e
      Rails.logger.error "[Webhooks::EmailMarketing] Mailchimp webhook error: #{e.message}"
      head :ok # Always return 200 to avoid retries
    end

    # POST /webhooks/email-marketing/constant-contact
    def constant_contact
      Rails.logger.info "[Webhooks::EmailMarketing] Received Constant Contact webhook"

      payload = request.body.read
      webhook_data = JSON.parse(payload) rescue {}

      # Verify webhook signature if configured
      unless verify_constant_contact_signature(payload)
        Rails.logger.warn "[Webhooks::EmailMarketing] Invalid Constant Contact webhook signature"
        head :unauthorized
        return
      end

      # Find the connection - Constant Contact includes account_id in webhook
      account_id = webhook_data['account_id']
      connection = find_constant_contact_connection(account_id)

      unless connection
        Rails.logger.warn "[Webhooks::EmailMarketing] No Constant Contact connection found for account #{account_id}"
        head :ok
        return
      end

      # Process the webhook asynchronously
      EmailMarketing::ProcessWebhookJob.perform_later(
        'constant_contact',
        connection.id,
        webhook_data.merge(received_at: Time.current.iso8601)
      )

      head :ok
    rescue StandardError => e
      Rails.logger.error "[Webhooks::EmailMarketing] Constant Contact webhook error: #{e.message}"
      head :ok
    end

    private

    def find_mailchimp_connection(list_id)
      return nil unless list_id.present?

      EmailMarketingConnection.mailchimp.active.find_by(default_list_id: list_id)
    end

    def find_constant_contact_connection(account_id)
      return nil unless account_id.present?

      EmailMarketingConnection.constant_contact.active.find_by(account_id: account_id)
    end

    def verify_constant_contact_signature(payload)
      # Constant Contact webhook signature verification
      # If no secret is configured, skip verification (development mode)
      secret = ENV['CONSTANT_CONTACT_WEBHOOK_SECRET']
      return true unless secret.present?

      signature = request.headers['X-CTCT-Signature']
      return false unless signature.present?

      expected = OpenSSL::HMAC.hexdigest('SHA256', secret, payload)
      ActiveSupport::SecurityUtils.secure_compare(signature, expected)
    end

    # Mailchimp webhook verification
    # Mailchimp doesn't send a signature header by default, so we verify by:
    # 1. Checking for a webhook secret if configured (preferred)
    # 2. Restricting to known Mailchimp IP addresses (fallback)
    #
    # Note: CSRF skip is acceptable here because we have this alternative verification.
    #
    # IP addresses are configured in config/initializers/email_marketing.rb
    # and can be overridden via the MAILCHIMP_WEBHOOK_IPS environment variable.
    def verify_mailchimp_request
      # Option 1: If a webhook secret is configured, verify it (preferred method)
      # Mailchimp can be configured to send a secret in the webhook URL or header
      secret = ENV['MAILCHIMP_WEBHOOK_SECRET']
      if secret.present?
        # Check if secret is passed as a query parameter (common Mailchimp pattern)
        return true if params[:secret].present? &&
                       ActiveSupport::SecurityUtils.secure_compare(params[:secret].to_s, secret)
      end

      # Option 2: In development/test, allow localhost
      return true if Rails.env.development? || Rails.env.test?

      # Option 3: Verify request comes from known Mailchimp IP addresses
      # These IPs are configured in config/initializers/email_marketing.rb
      # and sourced from https://mailchimp.com/about/ips/
      allowed_ips = Rails.application.config.email_marketing.mailchimp_webhook_ips
      remote_ip = request.remote_ip
      allowed_ips.include?(remote_ip)
    end
  end
end
