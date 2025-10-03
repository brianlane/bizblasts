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
      # Verify webhook signature if configured (similar to delivery_receipt)
      if verify_webhook_signature?
        unless valid_signature?
          Rails.logger.warn "Invalid Twilio inbound SMS signature"
          render json: { error: "Invalid signature" }, status: :forbidden
          return
        end
      end

      Rails.logger.info "Received Twilio inbound SMS: #{params.inspect}"
      
      # Extract message details
      from = params[:From] || params['From']
      body = params[:Body] || params['Body']
      message_sid = params[:MessageSid] || params['MessageSid']
      
      Rails.logger.info "Inbound SMS from #{from}: #{body}"
      
      # Process common keywords
      case body&.strip&.upcase
      when "HELP"
        Rails.logger.info "HELP keyword received from #{from}"
        # Send help response
        help_message = Sms::MessageTemplates.render('system.help_response', {
          business_name: 'BizBlasts',
          phone: ENV.fetch('SUPPORT_PHONE', '555-123-4567')
        })
        send_auto_reply(from, help_message) if help_message
        
      when "CANCEL", "STOP", "UNSUBSCRIBE"
        Rails.logger.info "STOP keyword received from #{from} - processing opt-out"
        process_sms_opt_out(from)
        
      when "START", "SUBSCRIBE", "YES"
        Rails.logger.info "START keyword received from #{from} - processing opt-in"
        process_sms_opt_in(from)
        
      when "CONFIRM"
        Rails.logger.info "CONFIRM keyword received from #{from}"
        # Could trigger booking confirmation logic here
        
      else
        Rails.logger.info "Other inbound message from #{from}: #{body}"
        # Send unknown command response for unrecognized messages
        if body.present? && body.length < 100 # Avoid responding to long messages
          unknown_message = Sms::MessageTemplates.render('system.unknown_command')
          send_auto_reply(from, unknown_message) if unknown_message
        end
      end
      
      # Always respond with success to acknowledge receipt
      render json: { status: "received" }, status: :ok
    end
    
    private
    
    def send_auto_reply(to_phone, message)
      # Find a business that can handle auto-replies
      # Try to find business associated with the phone number first
      business = find_business_for_auto_reply(to_phone)
      
      unless business
        Rails.logger.error "No suitable business found for auto-reply to #{to_phone}"
        return
      end
      
      # Send automatic reply via SMS service
      SmsService.send_message(to_phone, message, {
        business_id: business.id,
        auto_reply: true
      })
    rescue => e
      Rails.logger.error "Failed to send auto-reply to #{to_phone}: #{e.message}"
    end
    
    def find_business_for_auto_reply(phone_number)
      # Try to find business associated with this phone number
      normalized_phone = normalize_phone(phone_number)

      # Option 1: Find business through customer with this phone number
      customer = TenantCustomer.where(phone: normalized_phone).first
      return customer.business if customer&.business

      # Option 2: Find business through user with this phone number
      user = User.where(phone: normalized_phone).first
      return user.business if user&.business

      # Option 3: Fallback to any business that can send SMS (standard/premium tier only)
      Business.where(sms_enabled: true).where.not(tier: 'free').first || 
      Business.where.not(tier: 'free').first
    end
    
    def process_sms_opt_out(phone_number)
      # Determine business context from recent SMS activity
      business_context = determine_business_context(phone_number)

      if business_context
        Rails.logger.info "Processing business-specific opt-out for #{phone_number} from business #{business_context.id}"

        # Business-specific opt-out
        customers = TenantCustomer.where(phone: normalize_phone(phone_number), business: business_context)
        customers.each do |customer|
          customer.opt_out_from_business!(business_context)
          Rails.logger.info "Opted out customer #{customer.id} from business #{business_context.id}"
        end

        # Send business-specific confirmation
        opt_out_message = "You've been unsubscribed from #{business_context.name} SMS. Reply START to re-subscribe or HELP for assistance."
      else
        Rails.logger.info "Processing global opt-out for #{phone_number} (no business context found)"

        # Global opt-out (fallback)
        customers = TenantCustomer.where(phone: normalize_phone(phone_number))
        customers.each do |customer|
          customer.opt_out_of_sms!
          Rails.logger.info "Opted out customer #{customer.id} from SMS globally"
        end

        # Find users by phone number and opt them out
        users = User.where(phone: normalize_phone(phone_number))
        users.each do |user|
          if user.respond_to?(:opt_out_of_sms!)
            user.opt_out_of_sms!
            Rails.logger.info "Opted out user #{user.id} from SMS"
          end
        end

        opt_out_message = "You've been unsubscribed from all SMS. Reply START to re-subscribe or HELP for assistance."
      end

      send_auto_reply(phone_number, opt_out_message)
      Rails.logger.info "Processed SMS opt-out for #{phone_number}"
    end
    
    def process_sms_opt_in(phone_number)
      # Record any pending invitation responses
      record_invitation_response(phone_number, 'YES')

      # Determine business context
      business_context = determine_business_context(phone_number)

      if business_context
        Rails.logger.info "Processing business-specific opt-in for #{phone_number} to business #{business_context.id}"

        # Business-specific opt-in (remove from opted-out list and global opt-in)
        customers = TenantCustomer.where(phone: normalize_phone(phone_number), business: business_context)
        customers.each do |customer|
          customer.opt_in_to_business!(business_context) # Remove from business opt-out list
          customer.opt_into_sms! unless customer.phone_opt_in? # Global opt-in if not already
          Rails.logger.info "Opted in customer #{customer.id} for business #{business_context.id}"
        end

        # Send business-specific confirmation
        opt_in_message = "You're now subscribed to #{business_context.name} SMS notifications. Reply STOP to unsubscribe or HELP for assistance."
      else
        Rails.logger.info "Processing global opt-in for #{phone_number}"

        # Global opt-in
        customers = TenantCustomer.where(phone: normalize_phone(phone_number))
        customers.each do |customer|
          customer.opt_into_sms!
          Rails.logger.info "Opted in customer #{customer.id} for SMS"
        end

        opt_in_message = "You're now subscribed to SMS notifications. Reply STOP to unsubscribe or HELP for assistance."
      end

      send_auto_reply(phone_number, opt_in_message)
      Rails.logger.info "Processed SMS opt-in for #{phone_number}"
    end
    
    def normalize_phone(phone)
      # Basic phone normalization - remove all non-digits and add +1 if needed
      cleaned = phone.gsub(/\D/, '')
      cleaned = "1#{cleaned}" if cleaned.length == 10
      "+#{cleaned}"
    end
    
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

    # Determine business context from recent SMS activity
    def determine_business_context(phone_number)
      # Look for recent SMS messages from this phone number to identify business context
      recent_sms = SmsMessage.where(phone_number: normalize_phone(phone_number))
                            .where('sent_at > ?', 24.hours.ago)
                            .order(sent_at: :desc)
                            .first

      recent_sms&.business
    end

    # Record invitation response for analytics
    def record_invitation_response(phone_number, response_text)
      # Find recent invitations for this phone number
      recent_invitations = SmsOptInInvitation.where(phone_number: normalize_phone(phone_number))
                                            .where('sent_at > ?', 30.days.ago)
                                            .where(responded_at: nil)

      recent_invitations.each do |invitation|
        invitation.record_response!(response_text)
        Rails.logger.info "[SMS_INVITATION] Recorded response '#{response_text}' for invitation #{invitation.id}"
      end
    end
  end
end