# frozen_string_literal: true

module Webhooks
  class PlivoController < ActionController::API
    # For API-only controller, CSRF is not enabled by default.
    # Skip Devise-auth if present in parent modules (not included in ActionController::API, but guard anyway)
    skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)
    
    # Plivo webhook for delivery receipts
    def delivery_receipt
      Rails.logger.info "Received Plivo webhook: #{params.inspect}"
      
      # Verify webhook signature if configured
      if verify_webhook_signature?
        unless valid_signature?
          Rails.logger.error "Invalid Plivo webhook signature"
          render json: { error: "Invalid signature" }, status: :unauthorized
          return
        end
      end
      
      # Process the webhook through SmsService
      result = SmsService.process_webhook(params)
      
      if result[:success]
        Rails.logger.info "Plivo webhook processed successfully: #{result[:status]}"
        render json: { status: "success", message: "Webhook processed" }, status: :ok
      else
        Rails.logger.error "Plivo webhook processing failed: #{result[:error]}"
        render json: { error: result[:error] }, status: :unprocessable_entity
      end
      
    rescue => e
      Rails.logger.error "Plivo webhook error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: "Internal server error" }, status: :internal_server_error
    end
    
    # Future: Inbound SMS handler (not implemented yet)
    def inbound_message
      Rails.logger.info "Received Plivo inbound SMS: #{params.inspect}"
      
      # For now, just acknowledge the webhook
      render json: { status: "received" }, status: :ok
    end
    
    private
    
    def verify_webhook_signature?
      # Only verify signatures in production for security
      # Can be enabled in other environments by setting PLIVO_VERIFY_SIGNATURES=true
      Rails.env.production? || ENV['PLIVO_VERIFY_SIGNATURES'] == 'true'
    end
    
    def valid_signature?
      # Plivo webhook signature verification
      # This implements the signature verification as per Plivo's documentation
      
      signature = request.headers['X-Plivo-Signature-V2']
      return false unless signature
      
      # Get the raw POST body
      body = request.raw_post
      
      # Plivo signature verification algorithm:
      # 1. Concatenate the URL with the POST body
      # 2. Generate HMAC-SHA256 hash using auth token as key
      # 3. Base64 encode the result
      
      url = request.original_url
      data = url + body
      
      auth_token = PLIVO_AUTH_TOKEN
      expected_signature = Base64.strict_encode64(
        OpenSSL::HMAC.digest('sha256', auth_token, data)
      )
      
      # Secure comparison to prevent timing attacks
      ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
    rescue => e
      Rails.logger.error "Error verifying Plivo signature: #{e.message}"
      false
    end
  end
end