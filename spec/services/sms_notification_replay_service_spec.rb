# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SmsNotificationReplayService, type: :service do
  let(:business) { create(:business, sms_enabled: true) }
  let(:customer) { create(:tenant_customer, business: business, phone: '+15551234567', phone_opt_in: true, phone_opt_in_at: Time.current, skip_notification_email: true) }
  let(:service) { create(:service, business: business, name: 'Test Service') }
  let(:booking) { create(:booking, business: business, tenant_customer: customer, service: service, start_time: 1.day.from_now) }

  # Twilio mocking (following existing pattern from sms_service_spec.rb)
  let(:twilio_client) { instance_double(Twilio::REST::Client) }
  let(:twilio_messages) { double("Messages") }
  let(:twilio_response) { double("MessageResource", sid: "twilio-sid-replay-#{SecureRandom.hex(4)}") }

  before do
    # Mock Twilio client setup
    allow(Twilio::REST::Client).to receive(:new).with(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN).and_return(twilio_client)
    allow(twilio_client).to receive(:messages).and_return(twilio_messages)
    allow(twilio_messages).to receive(:create).and_return(twilio_response)

    # Enable SMS globally
    allow(Rails.application.config).to receive(:sms_enabled).and_return(true)

    # Mock SmsRateLimiter to allow sending by default
    allow(SmsRateLimiter).to receive(:can_send?).and_return(true)
    allow(SmsRateLimiter).to receive(:record_send).and_return(true)
  end

  around do |example|
    ActsAsTenant.with_tenant(business) do
      example.run
    end
  end

  describe '.replay_for_customer' do
    context 'with pending notifications' do
      let!(:notification1) { create(:pending_sms_notification, :booking_confirmation, business: business, tenant_customer: customer, booking: booking) }
      let!(:notification2) { create(:pending_sms_notification, :booking_reminder, business: business, tenant_customer: customer, booking: booking) }

      before do
        # Mock template rendering
        allow(Sms::MessageTemplates).to receive(:render).and_return('Mocked SMS message')
      end

      it 'replays all pending notifications' do
        results = described_class.replay_for_customer(customer)

        expect(results[:total]).to eq(2)
        expect(results[:sent]).to eq(2)
        expect(results[:failed]).to eq(0)
      end

      it 'marks notifications as sent' do
        described_class.replay_for_customer(customer)

        expect(notification1.reload.status).to eq('sent')
        expect(notification2.reload.status).to eq('sent')
        expect(notification1.processed_at).to be_present
        expect(notification2.processed_at).to be_present
      end

      it 'sends actual SMS via Twilio' do
        expect(twilio_messages).to receive(:create).twice.and_return(twilio_response)
        described_class.replay_for_customer(customer)
      end

      it 'records SMS sends for rate limiting' do
        expect(SmsRateLimiter).to receive(:record_send).with(business, customer).twice
        described_class.replay_for_customer(customer)
      end

      it 'adds delay between sends' do
        expect(described_class).to receive(:sleep).with(0.5).twice
        described_class.replay_for_customer(customer)
      end

      it 'logs replay progress' do
        expect(Rails.logger).to receive(:info).with("[SMS_REPLAY] Starting replay for customer #{customer.id}")
        expect(Rails.logger).to receive(:info).with("[SMS_REPLAY] Found 2 pending notifications for customer #{customer.id}")
        allow(Rails.logger).to receive(:info) # Allow other log statements

        described_class.replay_for_customer(customer)
      end
    end

    context 'with business-specific opt-in' do
      let(:other_business) { create(:business, sms_enabled: true) }
      let(:other_customer) { create(:tenant_customer, business: other_business, phone: customer.phone, phone_opt_in: true, phone_opt_in_at: Time.current, skip_notification_email: true) }

      let!(:business1_notification) { create(:pending_sms_notification, business: business, tenant_customer: customer) }
      let!(:business2_notification) { create(:pending_sms_notification, business: other_business, tenant_customer: other_customer) }

      before do
        allow(Sms::MessageTemplates).to receive(:render).and_return('Mocked SMS message')
      end

      it 'only replays notifications for specified business' do
        results = described_class.replay_for_customer(customer, business)

        expect(results[:total]).to eq(1)
        expect(results[:sent]).to eq(1)
      end

      it 'does not replay notifications from other businesses' do
        described_class.replay_for_customer(customer, business)

        expect(business1_notification.reload.status).to eq('sent')
        expect(business2_notification.reload.status).to eq('pending')
      end
    end

    context 'with no pending notifications' do
      it 'returns zero counts' do
        results = described_class.replay_for_customer(customer)

        expect(results[:total]).to eq(0)
        expect(results[:sent]).to eq(0)
        expect(results[:failed]).to eq(0)
      end

      it 'does not call SMS service' do
        expect(SmsService).not_to receive(:send_message)
        described_class.replay_for_customer(customer)
      end
    end

    context 'with expired notifications' do
      let!(:expired_notification) { create(:pending_sms_notification, :expired, business: business, tenant_customer: customer) }

      it 'does not process expired notifications' do
        results = described_class.replay_for_customer(customer)

        expect(results[:total]).to eq(0)
        expect(expired_notification.reload.status).to eq('expired')
      end
    end

    context 'with rate limiting' do
      let!(:notification) { create(:pending_sms_notification, business: business, tenant_customer: customer) }

      before do
        allow(Sms::MessageTemplates).to receive(:render).and_return('Mocked SMS message')
        allow(SmsRateLimiter).to receive(:can_send?).and_return(false)
      end

      it 'marks notifications as rate_limited' do
        results = described_class.replay_for_customer(customer)

        expect(results[:rate_limited]).to eq(1)
        expect(results[:sent]).to eq(0)
      end

      it 'does not mark notification as sent when rate limited' do
        described_class.replay_for_customer(customer)

        expect(notification.reload.status).to eq('pending')
      end

      it 'does not add delay when rate limited' do
        expect(described_class).not_to receive(:sleep)
        described_class.replay_for_customer(customer)
      end
    end
  end

  describe '.process_notification' do
    let(:notification) { create(:pending_sms_notification, :booking_confirmation, business: business, tenant_customer: customer, booking: booking) }

    before do
      allow(Sms::MessageTemplates).to receive(:render).and_return('Mocked SMS message')
    end

    context 'with valid notification' do
      it 'sends SMS successfully' do
        result = described_class.process_notification(notification)

        expect(result).to eq(:sent)
        expect(notification.reload.status).to eq('sent')
        expect(notification.processed_at).to be_present
      end

      it 'calls SmsService with correct parameters' do
        expect(SmsService).to receive(:send_message).with(
          customer.phone,
          'Mocked SMS message',
          hash_including(
            business_id: business.id,
            tenant_customer_id: customer.id,
            booking_id: booking.id
          )
        ).and_return({ success: true, sms_message: double("SmsMessage"), external_id: "test-sid" })

        described_class.process_notification(notification)
      end
    end

    context 'with expired notification' do
      let(:expired_notification) { create(:pending_sms_notification, business: business, tenant_customer: customer, expires_at: 1.day.ago) }

      it 'marks notification as expired' do
        result = described_class.process_notification(expired_notification)

        expect(result).to eq(:expired)
        expect(expired_notification.reload.status).to eq('expired')
      end

      it 'does not send SMS' do
        expect(SmsService).not_to receive(:send_message)
        described_class.process_notification(expired_notification)
      end
    end

    context 'when notification is not pending' do
      let(:sent_notification) { create(:pending_sms_notification, :sent, business: business, tenant_customer: customer) }

      it 'returns failed without processing' do
        result = described_class.process_notification(sent_notification)
        expect(result).to eq(:failed)
      end

      it 'logs warning' do
        expect(Rails.logger).to receive(:warn).with(/not pending/)
        described_class.process_notification(sent_notification)
      end
    end

    context 'when customer cannot receive SMS' do
      before do
        customer.update!(phone_opt_in: false)
      end

      it 'marks notification as failed' do
        result = described_class.process_notification(notification)

        expect(result).to eq(:failed)
        expect(notification.reload.status).to eq('failed')
        expect(notification.failure_reason).to include('still not opted in')
      end

      it 'does not send SMS' do
        expect(SmsService).not_to receive(:send_message)
        described_class.process_notification(notification)
      end
    end

    context 'when business cannot send SMS' do
      before do
        allow(Rails.logger).to receive(:warn) # Allow logger calls during update
        # Ensure customer check passes so we can test business check
        allow(customer).to receive(:can_receive_sms?).and_return(true)
        business.update!(sms_enabled: false)
      end

      it 'marks notification as failed' do
        result = described_class.process_notification(notification)

        expect(result).to eq(:failed)
        expect(notification.reload.status).to eq('failed')
        expect(notification.failure_reason).to include('Business no longer supports SMS')
      end

      it 'does not send SMS' do
        expect(SmsService).not_to receive(:send_message)
        described_class.process_notification(notification)
      end
    end

    context 'with rate limiting' do
      before do
        allow(SmsRateLimiter).to receive(:can_send?).and_return(false)
      end

      it 'returns rate_limited without marking as failed' do
        result = described_class.process_notification(notification)

        expect(result).to eq(:rate_limited)
        expect(notification.reload.status).to eq('pending')
      end

      it 'logs rate limit warning' do
        allow(Rails.logger).to receive(:info) # Allow other logger calls
        expect(Rails.logger).to receive(:info).with(/\[SMS_REPLAY\] Rate limit exceeded/)
        described_class.process_notification(notification)
      end
    end

    context 'when template rendering fails' do
      before do
        allow(Sms::MessageTemplates).to receive(:render).and_return(nil)
      end

      it 'marks notification as failed' do
        result = described_class.process_notification(notification)

        expect(result).to eq(:failed)
        expect(notification.reload.status).to eq('failed')
        expect(notification.failure_reason).to include('Failed to render SMS message template')
      end
    end

    context 'when SMS sending fails' do
      before do
        allow(SmsService).to receive(:send_message).and_return({ success: false, error: 'Twilio API error' })
      end

      it 'marks notification as failed' do
        result = described_class.process_notification(notification)

        expect(result).to eq(:failed)
        expect(notification.reload.status).to eq('failed')
        expect(notification.failure_reason).to eq('Twilio API error')
      end

      it 'logs error' do
        allow(Rails.logger).to receive(:error) # Allow other error logs
        expect(Rails.logger).to receive(:error).with(/\[SMS_REPLAY\] Failed to send/)
        described_class.process_notification(notification)
      end
    end

    context 'when exception occurs' do
      before do
        allow(SmsService).to receive(:send_message).and_raise(StandardError, 'Unexpected error')
      end

      it 'marks notification as failed' do
        result = described_class.process_notification(notification)

        expect(result).to eq(:failed)
        expect(notification.reload.status).to eq('failed')
        expect(notification.failure_reason).to include('Exception during processing')
      end

      it 'logs exception' do
        expect(Rails.logger).to receive(:error).with(/\[SMS_REPLAY\] Exception processing notification/).at_least(:once)
        allow(Rails.logger).to receive(:error) # For backtrace
        described_class.process_notification(notification)
      end
    end
  end

  describe 'template mapping' do
    let(:template_data) { { service_name: 'Test', date: '01/01/2025', time: '10:00 AM', business_name: 'Test Business' } }

    it 'maps booking_confirmation to correct template' do
      notification = create(:pending_sms_notification, notification_type: 'booking_confirmation', business: business, tenant_customer: customer, template_data: template_data)

      expect(Sms::MessageTemplates).to receive(:render).with('booking.confirmation', anything)
      described_class.send(:render_message, notification)
    end

    it 'maps booking_reminder to correct template' do
      notification = create(:pending_sms_notification, notification_type: 'booking_reminder', business: business, tenant_customer: customer, template_data: template_data)

      expect(Sms::MessageTemplates).to receive(:render).with('booking.reminder', anything)
      described_class.send(:render_message, notification)
    end

    it 'maps invoice_created to correct template' do
      notification = create(:pending_sms_notification, notification_type: 'invoice_created', business: business, tenant_customer: customer, template_data: template_data)

      expect(Sms::MessageTemplates).to receive(:render).with('invoice.created', anything)
      described_class.send(:render_message, notification)
    end

    it 'maps order_confirmation to correct template' do
      notification = create(:pending_sms_notification, notification_type: 'order_confirmation', business: business, tenant_customer: customer, template_data: template_data)

      expect(Sms::MessageTemplates).to receive(:render).with('order.confirmation', anything)
      described_class.send(:render_message, notification)
    end

    it 'returns nil for unknown notification type' do
      notification = create(:pending_sms_notification, notification_type: 'unknown_type', business: business, tenant_customer: customer, template_data: template_data)

      expect(Rails.logger).to receive(:error).with(/Unknown notification type/)
      result = described_class.send(:render_message, notification)
      expect(result).to be_nil
    end

    it 'handles template data as JSON string' do
      notification = create(:pending_sms_notification, business: business, tenant_customer: customer)
      notification.update_column(:template_data, '{"service_name": "Test"}')

      expect(Sms::MessageTemplates).to receive(:render).with('booking.confirmation', hash_including(service_name: 'Test'))
      described_class.send(:render_message, notification)
    end

    it 'handles template rendering errors' do
      notification = create(:pending_sms_notification, business: business, tenant_customer: customer, template_data: template_data)
      allow(Sms::MessageTemplates).to receive(:render).and_raise(StandardError, 'Template error')

      expect(Rails.logger).to receive(:error).with(/Failed to render template/)
      result = described_class.send(:render_message, notification)
      expect(result).to be_nil
    end
  end

  describe '.cleanup_expired!' do
    let!(:expired_notification) { create(:pending_sms_notification, business: business, tenant_customer: customer, expires_at: 1.day.ago, status: 'pending') }
    let!(:valid_notification) { create(:pending_sms_notification, business: business, tenant_customer: customer, status: 'pending') }

    it 'delegates to PendingSmsNotification model' do
      expect(PendingSmsNotification).to receive(:cleanup_expired!)
      described_class.cleanup_expired!
    end
  end

  describe '.stats' do
    let!(:notification) { create(:pending_sms_notification, business: business, tenant_customer: customer) }

    it 'delegates to PendingSmsNotification model' do
      expect(PendingSmsNotification).to receive(:stats)
      described_class.stats
    end
  end

  describe 'SMS options building' do
    context 'with booking notification' do
      let(:notification) { create(:pending_sms_notification, :booking_confirmation, business: business, tenant_customer: customer, booking: booking) }

      it 'includes booking_id in options' do
        options = described_class.send(:build_sms_options, notification)
        expect(options[:booking_id]).to eq(booking.id)
        expect(options[:business_id]).to eq(business.id)
        expect(options[:tenant_customer_id]).to eq(customer.id)
      end
    end

    context 'with invoice notification' do
      let(:invoice) { create(:invoice, business: business, tenant_customer: customer) }
      let(:notification) { create(:pending_sms_notification, :invoice_created, business: business, tenant_customer: customer, invoice: invoice) }

      it 'includes invoice_id in options' do
        options = described_class.send(:build_sms_options, notification)
        expect(options[:invoice_id]).to eq(invoice.id)
        expect(options[:business_id]).to eq(business.id)
        expect(options[:tenant_customer_id]).to eq(customer.id)
      end
    end

    context 'with order notification' do
      let(:order) { create(:order, business: business, tenant_customer: customer) }
      let(:notification) { create(:pending_sms_notification, :order_confirmation, business: business, tenant_customer: customer, order: order) }

      it 'includes order_id in options' do
        options = described_class.send(:build_sms_options, notification)
        expect(options[:order_id]).to eq(order.id)
        expect(options[:business_id]).to eq(business.id)
        expect(options[:tenant_customer_id]).to eq(customer.id)
      end
    end

    context 'without optional associations' do
      let(:notification) { create(:pending_sms_notification, business: business, tenant_customer: customer) }

      it 'only includes required options' do
        options = described_class.send(:build_sms_options, notification)
        expect(options[:booking_id]).to be_nil
        expect(options[:invoice_id]).to be_nil
        expect(options[:order_id]).to be_nil
        expect(options[:business_id]).to eq(business.id)
        expect(options[:tenant_customer_id]).to eq(customer.id)
      end
    end
  end
end
