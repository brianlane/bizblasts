# frozen_string_literal: true

module Webhooks
  class TwilioController < ActionController::API
    # For API-only controller, CSRF is not enabled by default.
    # Skip Devise-auth if present in parent modules (not included in ActionController::API, but guard anyway)
    skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)
    
    # Twilio webhook for delivery receipts
    def delivery_receipt
      Rails.logger.info "Received Twilio webhook: #{params.inspect}"
      
      # Verify webhook signature if configured
      if verify_webhook_signature?
        unless valid_signature?
          Rails.logger.error "Invalid Twilio webhook signature"
          render json: { error: "Invalid signature" }, status: :unauthorized
          return
        end
      end
      
      # Process the webhook through SmsService
      result = SmsService.process_webhook(params)
      
      if result[:success]
        Rails.logger.info "Twilio webhook processed successfully: #{result[:status]}"
        render json: { status: "success", message: "Webhook processed" }, status: :ok
      else
        Rails.logger.error "Twilio webhook processing failed: #{result[:error]}"
        render json: { error: result[:error] }, status: :unprocessable_content
      end
      
    rescue => e
      Rails.logger.error "Twilio webhook error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: "Internal server error" }, status: :internal_server_error
    end
    
    # Inbound SMS handler
    def inbound_message
      Rails.logger.info "Received Twilio inbound SMS: #{params.inspect}"
      
      # Extract message details
      from = params[:From] || params['From']
      body = params[:Body] || params['Body']
      message_sid = params[:MessageSid] || params['MessageSid']
      
      Rails.logger.info "Inbound SMS from #{from}: #{body}"
      
      # Process common keywords
      case body&.strip&.upcase
      when "HELP"
        # Handle HELP request
        Rails.logger.info "HELP keyword received from #{from}"
      when "CANCEL", "STOP"
        # Handle cancellation request
        Rails.logger.info "CANCEL/STOP keyword received from #{from}"
      when "CONFIRM"
        # Handle confirmation
        Rails.logger.info "CONFIRM keyword received from #{from}"
      else
        # Log other messages for future processing
        Rails.logger.info "Other inbound message from #{from}: #{body}"
      end
      
      # Always respond with success to acknowledge receipt
      render json: { status: "received" }, status: :ok
    end
    
    private
    
    def verify_webhook_signature?
      # Only verify signatures in production for security
      # Can be enabled in other environments by setting TWILIO_VERIFY_SIGNATURES=true
      Rails.env.production? || ENV['TWILIO_VERIFY_SIGNATURES'] == 'true'
    end
    
    def valid_signature?
      # Twilio webhook signature verification
      # This implements the signature verification as per Twilio's documentation
      
      signature = request.headers['X-Twilio-Signature']
      return false unless signature
      
      # Get the request URL and POST body
      url = request.original_url
      body = request.raw_post
      
      # Twilio signature verification using the Twilio SDK
      validator = Twilio::Security::RequestValidator.new(TWILIO_AUTH_TOKEN)
      validator.validate(url, body, signature)
      
    rescue => e
      Rails.logger.error "Error verifying Twilio signature: #{e.message}"
      false
    end
  end
end