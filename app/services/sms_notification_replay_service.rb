class SmsNotificationReplayService
  # Service for replaying pending SMS notifications when customers opt in

  class << self
    # Replay all pending notifications for a customer who just opted in
    def replay_for_customer(customer, business = nil)
      Rails.logger.info "[SMS_REPLAY] Starting replay for customer #{customer.id}"

      # Find pending notifications for this customer
      notifications = if business
        # Business-specific opt-in: only replay notifications for that business
        PendingSmsNotification.ready_for_processing
                             .for_customer(customer)
                             .for_business(business)
      else
        # Global opt-in: replay all pending notifications
        PendingSmsNotification.ready_for_processing
                             .for_customer(customer)
      end

      results = {
        total: notifications.count,
        sent: 0,
        failed: 0,
        expired: 0,
        rate_limited: 0
      }

      Rails.logger.info "[SMS_REPLAY] Found #{results[:total]} pending notifications for customer #{customer.id}"

      return results if results[:total] == 0

      # Process notifications one by one, respecting rate limits
      notifications.find_each do |notification|
        result = process_notification(notification)
        results[result] += 1

        # Add small delay between sends to respect rate limits
        sleep(0.5) if result == :sent
      end

      Rails.logger.info "[SMS_REPLAY] Completed replay for customer #{customer.id}: #{results}"
      results
    end

    # Process a single pending notification
    def process_notification(notification)
      # Double-check the notification is still valid
      if notification.expired?
        notification.mark_as_expired!
        return :expired
      end

      unless notification.pending?
        Rails.logger.warn "[SMS_REPLAY] Notification #{notification.id} is not pending (status: #{notification.status})"
        return :failed
      end

      # Verify customer can now receive SMS
      customer = notification.tenant_customer
      unless customer.can_receive_sms?(notification.sms_type.to_sym)
        Rails.logger.warn "[SMS_REPLAY] Customer #{customer.id} still cannot receive #{notification.sms_type} SMS"
        notification.mark_as_failed!("Customer still not opted in for #{notification.sms_type} SMS")
        return :failed
      end

      # Check business can still send SMS
      business = notification.business
      unless business.can_send_sms?
        Rails.logger.warn "[SMS_REPLAY] Business #{business.id} can no longer send SMS"
        notification.mark_as_failed!("Business no longer supports SMS")
        return :failed
      end

      # Check rate limits
      unless SmsRateLimiter.can_send?(business, customer)
        Rails.logger.info "[SMS_REPLAY] Rate limit exceeded for business #{business.id}, customer #{customer.id}"
        return :rate_limited
      end

      # Render the SMS message using the stored template data
      message = render_message(notification)
      unless message
        notification.mark_as_failed!("Failed to render SMS message template")
        return :failed
      end

      # Send the SMS
      result = SmsService.send_message(
        notification.phone_number,
        message,
        build_sms_options(notification)
      )

      if result[:success]
        # Record the send for rate limiting
        SmsRateLimiter.record_send(business, customer)
        notification.mark_as_sent!
        Rails.logger.info "[SMS_REPLAY] Successfully sent #{notification.notification_type} to #{customer.id}"
        :sent
      else
        notification.mark_as_failed!(result[:error] || "Unknown SMS sending error")
        Rails.logger.error "[SMS_REPLAY] Failed to send #{notification.notification_type} to #{customer.id}: #{result[:error]}"
        :failed
      end

    rescue => e
      notification.mark_as_failed!("Exception during processing: #{e.message}")
      Rails.logger.error "[SMS_REPLAY] Exception processing notification #{notification.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      :failed
    end

    # Cleanup expired notifications (can be called periodically)
    def cleanup_expired!
      PendingSmsNotification.cleanup_expired!
    end

    # Get statistics for monitoring
    def stats
      PendingSmsNotification.stats
    end

    private

    # Render SMS message using the notification's template data
    def render_message(notification)
      template_name = notification_type_to_template(notification.notification_type)
      return nil unless template_name

      template_data = notification.template_data.is_a?(String) ?
                      JSON.parse(notification.template_data) :
                      notification.template_data

      Sms::MessageTemplates.render(template_name, template_data.symbolize_keys)
    rescue => e
      Rails.logger.error "[SMS_REPLAY] Failed to render template for #{notification.notification_type}: #{e.message}"
      nil
    end

    # Map notification types to SMS template names
    def notification_type_to_template(notification_type)
      case notification_type
      when 'booking_confirmation'
        'booking.confirmation'
      when 'booking_reminder'
        'booking.reminder'
      when 'booking_status_update'
        'booking.status_update'
      when 'booking_cancellation'
        'booking.cancellation'
      when 'booking_payment_reminder'
        'booking.payment_reminder'
      when 'invoice_created'
        'invoice.created'
      when 'invoice_payment_confirmation'
        'invoice.payment_confirmation'
      when 'invoice_payment_reminder'
        'invoice.payment_reminder'
      when 'invoice_payment_failed'
        'invoice.payment_failed'
      when 'order_confirmation'
        'order.confirmation'
      when 'order_status_update'
        'order.status_update'
      when 'order_refund_confirmation'
        'order.refund_confirmation'
      when 'subscription_booking_created'
        'booking.subscription_booking_created'
      when 'subscription_order_created'
        'order.subscription_order_created'
      else
        Rails.logger.error "[SMS_REPLAY] Unknown notification type: #{notification_type}"
        nil
      end
    end

    # Build options hash for SmsService.send_message
    def build_sms_options(notification)
      options = {
        business_id: notification.business_id,
        tenant_customer_id: notification.tenant_customer_id
      }

      # Add specific association IDs if present
      options[:booking_id] = notification.booking_id if notification.booking_id
      options[:invoice_id] = notification.invoice_id if notification.invoice_id
      options[:order_id] = notification.order_id if notification.order_id

      options
    end
  end
end