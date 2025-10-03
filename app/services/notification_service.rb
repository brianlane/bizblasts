class NotificationService
  # Unified service for sending both email and SMS notifications
  # This ensures consistent delivery across all communication channels
  
  class << self
    # Booking notifications
    def booking_confirmation(booking)
      send_email_and_sms(
        email: -> { BookingMailer.confirmation(booking).deliver_later },
        sms: -> { SmsService.send_booking_confirmation(booking) },
        recipient: booking.tenant_customer,
        email_type: :booking,
        sms_type: :booking
      )
    end

    def booking_status_update(booking)
      send_email_and_sms(
        email: -> { BookingMailer.status_update(booking).deliver_later },
        sms: -> { SmsService.send_booking_status_update(booking) },
        recipient: booking.tenant_customer,
        email_type: :booking,
        sms_type: :booking
      )
    end

    def booking_cancellation(booking)
      send_email_and_sms(
        email: -> { BookingMailer.cancellation(booking).deliver_later },
        sms: -> { SmsService.send_booking_cancellation(booking) },
        recipient: booking.tenant_customer,
        email_type: :booking,
        sms_type: :booking
      )
    end

    def booking_reminder(booking, time_before = nil)
      send_email_and_sms(
        email: -> { BookingMailer.reminder(booking, time_before).deliver_later },
        sms: -> { SmsService.send_booking_reminder(booking, time_before) },
        recipient: booking.tenant_customer,
        email_type: :booking,
        sms_type: :reminder
      )
    end

    def booking_payment_reminder(booking)
      send_email_and_sms(
        email: -> { BookingMailer.payment_reminder(booking).deliver_later },
        sms: -> { SmsService.send_booking_payment_reminder(booking) },
        recipient: booking.tenant_customer,
        email_type: :payment,
        sms_type: :payment
      )
    end

    def subscription_booking_created(booking)
      send_email_and_sms(
        email: -> { BookingMailer.subscription_booking_created(booking).deliver_later },
        sms: -> { SmsService.send_subscription_booking_created(booking) },
        recipient: booking.tenant_customer,
        email_type: :subscription,
        sms_type: :subscription
      )
    end

    # Invoice notifications
    def invoice_created(invoice)
      send_email_and_sms(
        email: -> { InvoiceMailer.invoice_created(invoice).deliver_later },
        sms: -> { SmsService.send_invoice_created(invoice) },
        recipient: invoice.tenant_customer,
        email_type: :payment,
        sms_type: :transactional
      )
    end

    def invoice_payment_confirmation(invoice, payment)
      send_email_and_sms(
        email: -> { InvoiceMailer.payment_confirmation(invoice, payment).deliver_later },
        sms: -> { SmsService.send_invoice_payment_confirmation(invoice, payment) },
        recipient: invoice.tenant_customer,
        email_type: :payment,
        sms_type: :transactional
      )
    end

    def invoice_payment_reminder(invoice)
      send_email_and_sms(
        email: -> { InvoiceMailer.payment_reminder(invoice).deliver_later },
        sms: -> { SmsService.send_invoice_payment_reminder(invoice) },
        recipient: invoice.tenant_customer,
        email_type: :payment,
        sms_type: :payment
      )
    end

    def invoice_payment_failed(invoice, payment)
      send_email_and_sms(
        email: -> { InvoiceMailer.payment_failed(invoice, payment).deliver_later },
        sms: -> { SmsService.send_invoice_payment_failed(invoice, payment) },
        recipient: invoice.tenant_customer,
        email_type: :payment,
        sms_type: :payment
      )
    end

    # Order notifications
    def order_confirmation(order)
      send_email_and_sms(
        email: -> { OrderMailer.order_confirmation(order).deliver_later },
        sms: -> { SmsService.send_order_confirmation(order) },
        recipient: order.tenant_customer,
        email_type: :order,
        sms_type: :transactional
      )
    end

    def order_status_update(order, previous_status)
      send_email_and_sms(
        email: -> { OrderMailer.order_status_update(order, previous_status).deliver_later },
        sms: -> { SmsService.send_order_status_update(order, previous_status) },
        recipient: order.tenant_customer,
        email_type: :order,
        sms_type: :booking
      )
    end

    def order_refund_confirmation(order, payment)
      send_email_and_sms(
        email: -> { OrderMailer.refund_confirmation(order, payment).deliver_later },
        sms: -> { SmsService.send_order_refund_confirmation(order, payment) },
        recipient: order.tenant_customer,
        email_type: :payment,
        sms_type: :payment
      )
    end

    def subscription_order_created(order)
      send_email_and_sms(
        email: -> { OrderMailer.subscription_order_created(order).deliver_later },
        sms: -> { SmsService.send_subscription_order_created(order) },
        recipient: order.tenant_customer,
        email_type: :subscription,
        sms_type: :subscription
      )
    end

    # Business notifications (to business owners/managers)
    def business_new_booking(booking)
      business_user = booking.business.users.where(role: :manager).first
      return unless business_user
      
      send_email_and_sms(
        email: -> { BusinessMailer.new_booking_notification(booking).deliver_later },
        sms: -> { SmsService.send_business_new_booking(booking, business_user) },
        recipient: business_user,
        email_type: :booking,
        sms_type: :booking
      )
    end

    def business_new_order(order)
      business_user = order.business.users.where(role: :manager).first
      return unless business_user
      
      send_email_and_sms(
        email: -> { BusinessMailer.new_order_notification(order).deliver_later },
        sms: -> { SmsService.send_business_new_order(order, business_user) },
        recipient: business_user,
        email_type: :order,
        sms_type: :booking
      )
    end

    def business_payment_received(payment)
      business_user = payment.business.users.where(role: :manager).first
      return unless business_user
      
      send_email_and_sms(
        email: -> { BusinessMailer.payment_received_notification(payment).deliver_later },
        sms: -> { SmsService.send_business_payment_received(payment, business_user) },
        recipient: business_user,
        email_type: :payment,
        sms_type: :payment
      )
    end

    # Marketing notifications
    def marketing_campaign(campaign, recipient)
      send_email_and_sms(
        email: -> { MarketingMailer.campaign(recipient, campaign).deliver_later },
        sms: -> { SmsService.send_marketing_campaign(campaign, recipient) },
        recipient: recipient,
        email_type: :marketing,
        sms_type: :marketing
      )
    end

    private

    def send_email_and_sms(email:, sms:, recipient:, email_type:, sms_type:)
      results = { email: false, sms: false }
      
      # Send email if recipient can receive this type
      if recipient.can_receive_email?(email_type)
        begin
          email.call
          results[:email] = true
          Rails.logger.info "[NOTIFICATION] Email sent to #{recipient.email} for #{email_type}"
        rescue => e
          Rails.logger.error "[NOTIFICATION] Email failed to #{recipient.email}: #{e.message}"
        end
      end

      # Send SMS if recipient can receive this type
      if recipient.respond_to?(:can_receive_sms?) && recipient.can_receive_sms?(sms_type)
        begin
          sms_result = sms.call
          # Handle various SMS result formats more robustly
          sms_success = case sms_result
                       when Hash
                         sms_result[:success] == true
                       when true
                         true
                       else
                         # nil, false, or any other value is considered failure
                         false
                       end

          if sms_success
            results[:sms] = true
            Rails.logger.info "[NOTIFICATION] SMS sent to #{recipient.phone} for #{sms_type}"
          else
            error_msg = sms_result.is_a?(Hash) ? sms_result[:error] : sms_result.to_s
            Rails.logger.info "[NOTIFICATION] SMS not sent to #{recipient.phone} for #{sms_type}: #{error_msg || 'opt-in required or rate limited'}"
          end
        rescue => e
          Rails.logger.error "[NOTIFICATION] SMS failed to #{recipient.phone || 'phone'}: #{e.message}"
        end
      end

      results
    end
  end
end