# frozen_string_literal: true

module Webhooks
  # Handles incoming webhooks from email marketing platforms (Mailchimp, Constant Contact)
  class EmailMarketingController < ApplicationController
    # Only skip CSRF verification for webhook POST endpoints called by external services
    # The mailchimp_verify GET action doesn't need CSRF skipped (GET requests are exempt)
    # but we explicitly limit skip_before_action to only the POST webhook actions
    skip_before_action :verify_authenticity_token, only: [:mailchimp, :constant_contact]

    # Mailchimp sends a GET request to verify the webhook URL
    # GET /webhooks/email-marketing/mailchimp
    def mailchimp_verify
      render plain: 'OK', status: :ok
    end

    # POST /webhooks/email-marketing/mailchimp
    def mailchimp
      Rails.logger.info "[Webhooks::EmailMarketing] Received Mailchimp webhook"

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
  end
end
