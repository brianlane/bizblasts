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

      # Find or create tenant customer for this phone number and business
      normalized_phone = normalize_phone(to_phone)
      tenant_customer = TenantCustomer.find_by(phone: normalized_phone, business: business)

      # If no tenant customer exists, try to find a user and link them
      unless tenant_customer
        user = User.find_by(phone: normalized_phone)
        if user
          Rails.logger.info "Found user #{user.id} for phone #{to_phone}, linking to business #{business.id}"
          begin
            tenant_customer = CustomerLinker.new(business).link_user_to_customer(user)
            Rails.logger.info "Successfully linked user #{user.id} to tenant customer #{tenant_customer.id}"
          rescue => linking_error
            Rails.logger.error "Failed to link user #{user.id} to business #{business.id}: #{linking_error.message}"
            return
          end
        else
          Rails.logger.info "Creating minimal tenant customer for new phone number #{to_phone} in business #{business.id}"
          begin
            # Create minimal tenant customer record for completely new phone numbers
            # This enables auto-replies for new users discovered through SMS interactions
            tenant_customer = TenantCustomer.create!(
              business: business,
              phone: normalized_phone,
              first_name: 'Unknown', # Will be updated when they provide more info
              last_name: 'User',     # Will be updated when they provide more info
              email: "sms-user-#{SecureRandom.hex(8)}@temp.bizblasts.com", # Temporary email to satisfy validation
              phone_opt_in: false   # Start with opt-out, they need to explicitly opt-in
            )
            Rails.logger.info "Created minimal tenant customer #{tenant_customer.id} for phone #{to_phone}"
          rescue => creation_error
            Rails.logger.error "Failed to create tenant customer for phone #{to_phone}: #{creation_error.message}"
            return
          end
        end
      end

      # Send automatic reply via SMS service
      SmsService.send_message(to_phone, message, {
        business_id: business.id,
        tenant_customer_id: tenant_customer.id,
        auto_reply: true
      })
    rescue => e
      Rails.logger.error "Failed to send auto-reply to #{to_phone}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
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
          customer.opt_out_of_sms! # Also update global opt-in status
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

      # Ensure customer exists before processing opt-in
      # This prevents timing issues where new users text "YES" as first interaction
      ensure_customer_exists(phone_number, business_context)

      if business_context
        Rails.logger.info "Processing business-specific opt-in for #{phone_number} to business #{business_context.id}"

        # Business-specific opt-in (remove from opted-out list and global opt-in)
        customers = TenantCustomer.where(phone: normalize_phone(phone_number), business: business_context)
        customers.each do |customer|
          customer.opt_in_to_business!(business_context) # Remove from business opt-out list
          customer.opt_into_sms! unless customer.phone_opt_in? # Global opt-in if not already
          Rails.logger.info "Opted in customer #{customer.id} for business #{business_context.id}"

          # Schedule replay of pending notifications for this customer and business
          schedule_notification_replay(customer, business_context)
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

          # Schedule replay of all pending notifications for this customer
          schedule_notification_replay(customer, nil)
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
      # Verify signatures in production unless explicitly disabled
      # Can be disabled by setting TWILIO_VERIFY_SIGNATURES=false
      # Can be enabled in other environments by setting TWILIO_VERIFY_SIGNATURES=true
      if Rails.env.production?
        ENV['TWILIO_VERIFY_SIGNATURES'] != 'false'
      else
        ENV['TWILIO_VERIFY_SIGNATURES'] == 'true'
      end
    end
    
    def valid_signature?
      # Twilio webhook signature verification
      # This implements the signature verification as per Twilio's documentation

      signature = request.headers['X-Twilio-Signature']
      return false unless signature

      # Get the request URL and POST body
      # Use the URL Twilio actually called (before any redirects)
      # If the request was redirected from bizblasts.com to www.bizblasts.com,
      # we need to use the original URL for signature validation
      url = reconstruct_original_url
      body = request.raw_post

      # Debug logging for signature validation
      Rails.logger.info "[WEBHOOK] Signature validation: URL=#{url}, Signature=#{signature[0..10]}..."

      # Twilio signature verification using the Twilio SDK
      validator = Twilio::Security::RequestValidator.new(TWILIO_AUTH_TOKEN)
      result = validator.validate(url, body, signature)

      Rails.logger.info "[WEBHOOK] Signature validation result: #{result}"
      result

    rescue => e
      Rails.logger.error "Error verifying Twilio signature: #{e.message}"
      false
    end

    def reconstruct_original_url
      # If request came to www.bizblasts.com but Twilio called bizblasts.com,
      # we need to reconstruct the original URL for signature validation
      current_url = request.original_url

      # In production, Twilio is configured to call bizblasts.com (without www)
      # but Rails redirects to www.bizblasts.com
      if Rails.env.production? && current_url.include?('www.bizblasts.com')
        # Replace www.bizblasts.com with bizblasts.com for signature validation
        original_url = current_url.gsub('www.bizblasts.com', 'bizblasts.com')
        Rails.logger.debug "[WEBHOOK] URL reconstruction: #{current_url} -> #{original_url}"
        original_url
      else
        # In other environments, use the current URL as-is
        current_url
      end
    end

    # Determine business context using multiple signals
    # Improved to handle new users without SMS history
    def determine_business_context(phone_number)
      normalized_phone = normalize_phone(phone_number)

      # Strategy 1: Recent SMS messages (original logic, but extended timeframe)
      recent_sms = SmsMessage.where(phone_number: normalized_phone)
                            .where('sent_at > ?', 7.days.ago) # Extended from 24 hours
                            .order(sent_at: :desc)
                            .first
      return recent_sms.business if recent_sms&.business

      # Strategy 2: Recent SMS opt-in invitations
      # If they received an invitation recently, use that business context
      recent_invitation = SmsOptInInvitation.where(phone_number: normalized_phone)
                                           .where('sent_at > ?', 30.days.ago)
                                           .order(sent_at: :desc)
                                           .first
      return recent_invitation.business if recent_invitation&.business

      # Strategy 3: Existing customer records
      # If they're already a customer of a business, prefer that context
      customer_businesses = TenantCustomer.where(phone: normalized_phone)
                                         .joins(:business)
                                         .where(businesses: { sms_enabled: true })
                                         .includes(:business)
                                         .order('tenant_customers.created_at DESC')
      return customer_businesses.first.business if customer_businesses.exists?

      # Strategy 4: User business association
      # If a User record exists with this phone, use their business
      user = User.where(phone: normalized_phone).first
      if user&.business&.sms_enabled?
        return user.business
      end

      # Strategy 5: Recent booking/order activity
      # Check for recent business interactions through bookings or orders
      recent_booking_business = find_business_from_recent_bookings(normalized_phone)
      return recent_booking_business if recent_booking_business

      # Strategy 6: Smart fallback - most active SMS business
      # Use the business that sends the most SMS (likely the main business)
      fallback_business = Business.joins(:sms_messages)
                                 .where(sms_enabled: true)
                                 .where.not(tier: 'free')
                                 .where('sms_messages.sent_at > ?', 30.days.ago)
                                 .group('businesses.id')
                                 .order('COUNT(sms_messages.id) DESC')
                                 .first

      Rails.logger.info "[BUSINESS_CONTEXT] Using fallback business #{fallback_business&.id} for #{phone_number}" if fallback_business
      fallback_business
    end

    # Find business from recent booking/order activity
    def find_business_from_recent_bookings(phone_number)
      normalized_phone = normalize_phone(phone_number)

      # Check for recent bookings by tenant customers
      if defined?(Booking)
        recent_booking = Booking.joins(:tenant_customer)
                               .where(tenant_customers: { phone: normalized_phone })
                               .where('bookings.created_at > ?', 90.days.ago)
                               .order('bookings.created_at DESC')
                               .first
        return recent_booking.business if recent_booking&.business&.sms_enabled?

        # Also check for bookings placed by client users (without tenant customer)
        recent_user_booking = Booking.joins(:user)
                                    .where(users: { phone: normalized_phone })
                                    .where('bookings.created_at > ?', 90.days.ago)
                                    .order('bookings.created_at DESC')
                                    .first
        return recent_user_booking.business if recent_user_booking&.business&.sms_enabled?
      end

      # Check for recent orders by tenant customers
      if defined?(Order)
        recent_order = Order.joins(:tenant_customer)
                           .where(tenant_customers: { phone: normalized_phone })
                           .where('orders.created_at > ?', 90.days.ago)
                           .order('orders.created_at DESC')
                           .first
        return recent_order.business if recent_order&.business&.sms_enabled?

        # Also check for orders placed by client users (without tenant customer)
        recent_user_order = Order.joins(:user)
                                .where(users: { phone: normalized_phone })
                                .where('orders.created_at > ?', 90.days.ago)
                                .order('orders.created_at DESC')
                                .first
        return recent_user_order.business if recent_user_order&.business&.sms_enabled?
      end

      nil
    rescue => e
      Rails.logger.warn "[BUSINESS_CONTEXT] Error checking recent bookings/orders for #{phone_number}: #{e.message}"
      nil
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

    # Schedule replay of pending SMS notifications after opt-in
    def schedule_notification_replay(customer, business = nil)
      # Check if there are any pending notifications for this customer
      pending_count = if business
        PendingSmsNotification.pending
                             .for_customer(customer)
                             .for_business(business)
                             .count
      else
        PendingSmsNotification.pending
                             .for_customer(customer)
                             .count
      end

      if pending_count > 0
        Rails.logger.info "[SMS_REPLAY] Scheduling replay for customer #{customer.id} (#{business&.id || 'all businesses'}) - #{pending_count} pending notifications"

        # Schedule the replay job (immediate for webhook response time)
        SmsNotificationReplayJob.schedule_for_customer(customer, business)

        Rails.logger.info "[SMS_REPLAY] Replay job scheduled for customer #{customer.id}"
      else
        Rails.logger.info "[SMS_REPLAY] No pending notifications for customer #{customer.id} (#{business&.id || 'all businesses'})"
      end
    rescue => e
      Rails.logger.error "[SMS_REPLAY] Error scheduling replay for customer #{customer.id}: #{e.message}"
      # Don't raise - this shouldn't break the webhook response
    end

    # Ensure a customer record exists for the phone number before processing opt-in
    # This prevents timing issues where new users text "YES" as their first interaction
    def ensure_customer_exists(phone_number, business_context = nil)
      normalized_phone = normalize_phone(phone_number)

      # If we have business context, check if customer exists for that business
      if business_context
        existing_customer = TenantCustomer.find_by(phone: normalized_phone, business: business_context)
        return if existing_customer

        Rails.logger.info "Creating customer for opt-in: phone #{phone_number}, business #{business_context.id}"

        # Try to find user and link, or create minimal customer
        user = User.find_by(phone: normalized_phone)
        if user
          begin
            CustomerLinker.new(business_context).link_user_to_customer(user)
            Rails.logger.info "Linked existing user #{user.id} to business #{business_context.id} for opt-in"
          rescue => linking_error
            Rails.logger.error "Failed to link user for opt-in: #{linking_error.message}"
            # Fall through to create minimal customer
            create_minimal_customer(normalized_phone, business_context)
          end
        else
          create_minimal_customer(normalized_phone, business_context)
        end
      else
        # No business context - ensure at least one customer exists for this phone
        existing_customers = TenantCustomer.where(phone: normalized_phone)
        return if existing_customers.exists?

        Rails.logger.info "Creating customer for global opt-in: phone #{phone_number}"

        # Find any business that can handle SMS
        fallback_business = Business.where(sms_enabled: true).where.not(tier: 'free').first ||
                           Business.where.not(tier: 'free').first

        if fallback_business
          create_minimal_customer(normalized_phone, fallback_business)
        else
          Rails.logger.error "No suitable business found for global opt-in customer creation"
        end
      end
    rescue => e
      Rails.logger.error "Failed to ensure customer exists for #{phone_number}: #{e.message}"
      # Don't raise - this shouldn't break the opt-in process
    end

    # Create a minimal customer record for SMS interactions
    def create_minimal_customer(phone, business)
      TenantCustomer.create!(
        business: business,
        phone: phone,
        first_name: 'Unknown',
        last_name: 'User',
        email: "sms-user-#{SecureRandom.hex(8)}@temp.bizblasts.com",
        phone_opt_in: false # Will be set to true by opt-in process
      )
      Rails.logger.info "Created minimal customer for phone #{phone} in business #{business.id}"
    rescue => e
      Rails.logger.error "Failed to create minimal customer for #{phone}: #{e.message}"
      raise # Re-raise so caller can handle
    end
  end
end