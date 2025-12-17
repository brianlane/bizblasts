# frozen_string_literal: true

module Webhooks
  # Handles incoming webhooks from email marketing platforms (Mailchimp, Constant Contact)
  class EmailMarketingController < ApplicationController
    # SECURITY: External webhook endpoints (CWE-352 / CSRF)
    #
    # Webhooks are server-to-server callbacks and cannot include Rails CSRF tokens.
    # Instead of disabling CSRF verification (which CodeQL flags), we keep forgery
    # protection enabled but use the `null_session` strategy so unverified requests
    # cannot leverage cookie-backed session state.
    #
    # Defense-in-depth authentication:
    # - `mailchimp`: request source verification (secret param and/or IP allowlist)
    # - `constant_contact`: HMAC signature verification (`X-CTCT-Signature`)
    # codeql[rb/csrf-protection-disabled] Webhooks cannot use CSRF tokens; we use signature/IP verification
    protect_from_forgery with: :null_session

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
      webhook_data = params['data'] || params.to_unsafe_h.except('controller', 'action')
      list_id = webhook_data['list_id'] || params['data[list_id]']

      # Find the connection for this list
      connection = find_mailchimp_connection(list_id)

      unless connection
        Rails.logger.warn "[Webhooks::EmailMarketing] No Mailchimp connection found for list #{list_id}"
        head :ok
        return
      end

      # Process the webhook asynchronously
      EmailMarketing::ProcessWebhookJob.perform_later(
        'mailchimp',
        connection.id,
        {
          type: webhook_type,
          data: webhook_data.to_h,
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
    def verify_mailchimp_request
      # Option 1: If a webhook secret is configured, verify it
      # (Mailchimp can be configured to send a secret in the webhook URL or header)
      secret = ENV['MAILCHIMP_WEBHOOK_SECRET']
      if secret.present?
        # Check if secret is passed as a query parameter (common Mailchimp pattern)
        return true if params[:secret].present? &&
                       ActiveSupport::SecurityUtils.secure_compare(params[:secret].to_s, secret)
      end

      # Option 2: Verify request comes from known Mailchimp IP addresses
      # These are Mailchimp's published webhook IP ranges from https://mailchimp.com/about/ips/
      # Last updated: December 2024. Review periodically for changes.
      allowed_ips = [
        '52.23.45.43',
        '52.204.253.38',
        '52.204.255.205',
        '54.85.123.78',
        '54.87.214.91',
        '54.208.115.215',
        '54.209.221.135',
        '54.221.253.203',
        '54.224.62.94',
        '54.224.148.131',
        '54.226.12.205',
        '54.227.4.208',
        '54.227.107.57',
        '54.231.189.82',
        '54.231.242.40',
        '54.237.188.163',
        '54.242.175.77'
      ]

      # In development/test, allow localhost
      return true if Rails.env.development? || Rails.env.test?

      # Check if remote IP is in allowed list
      remote_ip = request.remote_ip
      allowed_ips.include?(remote_ip)
    end
  end
end
