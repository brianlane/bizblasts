 # frozen_string_literal: true

module ClientDocuments
  class ExperienceBookingProcessor
    def self.process!(document:, payment:, session:)
      new(document, payment, session).process!
    end

    def initialize(document, payment, session)
      @document = document
      @payment = payment
      @session = session
      @business = document.business
      @tenant_customer = document.tenant_customer
    end

    def process!
      return unless booking_payload.present?
      return unless @business && @tenant_customer

      ActsAsTenant.with_tenant(@business) do
        ActiveRecord::Base.transaction do
          persist_stripe_customer!
          booking = create_booking!
          create_add_ons!(booking)
          invoice = create_invoice!(booking)
          update_payment_invoice!(invoice)
          send_notifications(booking, invoice)

          @document.update!(
            documentable: booking,
            invoice: invoice,
            metadata: (@document.metadata || {}).merge('booking_id' => booking.id)
          )
          @document.record_event!('booking_created', booking_id: booking.id)
        end
      end
    end

    private

    def booking_payload
      raw_payload = @document.metadata['booking_payload']
      return unless raw_payload.present?

      @booking_payload ||= raw_payload.deep_symbolize_keys
    end

    def persist_stripe_customer!
      return if @session['customer'].blank?
      return if @tenant_customer.stripe_customer_id.present?

      @tenant_customer.update!(stripe_customer_id: @session['customer'])
    end

    def create_booking!
      status = if @business.booking_policy.nil? || @business.booking_policy.auto_confirm_bookings?
                 :confirmed
               else
                 :pending
               end

      raw_quantity = @document.metadata.dig('booking_payload', 'quantity')
      raw_quantity = booking_payload[:quantity] if raw_quantity.blank?
      quantity_value = raw_quantity.to_i
      quantity_value = 1 if quantity_value <= 0

      attrs = {
        service_id: booking_payload[:service_id],
        service_variant_id: booking_payload[:service_variant_id],
        staff_member_id: booking_payload[:staff_member_id],
        start_time: Time.parse(booking_payload[:start_time]),
        end_time: Time.parse(booking_payload[:end_time]),
        notes: booking_payload[:notes],
        tenant_customer: @tenant_customer,
        status: status,
        quantity: quantity_value
      }

      if booking_payload[:applied_promo_code].present?
        attrs[:applied_promo_code] = booking_payload[:applied_promo_code]
        attrs[:promo_code_type] = booking_payload[:promo_code_type]
        attrs[:promo_discount_amount] = booking_payload[:promo_discount_amount]
      end

      booking = @business.bookings.create!(attrs)
      if booking.quantity != quantity_value
        booking.update_column(:quantity, quantity_value)
        booking.reload
      end
      booking
    end

    def create_add_ons!(booking)
      Array(booking_payload[:booking_product_add_ons]).each do |addon|
        next if addon[:quantity].to_i <= 0
        next if addon[:product_variant_id].blank?

        booking.booking_product_add_ons.create!(
          product_variant_id: addon[:product_variant_id],
          quantity: addon[:quantity]
        )
      end
    end

    def create_invoice!(booking)
      invoice = booking.build_invoice(
        tenant_customer: @tenant_customer,
        business: @business,
        tax_rate: @business.default_tax_rate,
        due_date: booking.start_time.to_date,
        status: :paid
      )
      invoice.save!
      invoice
    end

    def update_payment_invoice!(invoice)
      return unless @payment && invoice

      @payment.update!(invoice: invoice)
    end

    def send_notifications(booking, invoice)
      if @payment
        NotificationService.invoice_payment_confirmation(invoice, @payment)
      end

      NotificationService.business_new_booking(booking)
      NotificationService.business_payment_received(@payment) if @payment
      NotificationService.booking_confirmation(booking)
    rescue => e
      Rails.logger.error "[CLIENT_DOCUMENT] Failed to send booking notifications: #{e.message}"
    end
  end
end
