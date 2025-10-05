# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Twilio Inbound SMS Webhooks', type: :request do
  let(:business) { create(:business, sms_enabled: true, tier: 'premium') }
  let(:customer) { create(:tenant_customer, business: business, phone: '+16026866672', phone_opt_in: false) }

  # Mock Twilio webhook parameters
  let(:twilio_params) do
    {
      'From' => customer.phone,
      'To' => '+18556128814',
      'Body' => 'YES',
      'MessageSid' => 'SM123456789',
      'AccountSid' => 'AC123456789',
      'MessagingServiceSid' => 'MG123456789'
    }
  end

  before do
    # Disable signature verification for testing
    allow_any_instance_of(Webhooks::TwilioController).to receive(:verify_webhook_signature?).and_return(false)

    # Mock SmsService to avoid actual Twilio calls
    allow(SmsService).to receive(:send_message).and_return({ success: true })
  end

  describe 'POST /webhooks/twilio/inbound' do
    context 'when customer replies YES to opt-in' do
      it 'processes opt-in successfully and sends confirmation' do
        expect {
          post '/webhooks/twilio/inbound', params: twilio_params
        }.to change { customer.reload.phone_opt_in? }.from(false).to(true)

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['status']).to eq('received')
      end

      it 'sends confirmation message via auto-reply' do
        expect(SmsService).to receive(:send_message).with(
          customer.phone,
          match(/You're now subscribed to SMS notifications/),
          hash_including(business_id: business.id, tenant_customer_id: customer.id, auto_reply: true)
        )

        post '/webhooks/twilio/inbound', params: twilio_params
      end

      it 'schedules notification replay if pending notifications exist' do
        # Create a recent SMS message to establish business context
        SmsMessage.create!(
          phone_number: customer.phone,
          content: 'Previous message',
          status: 'sent',
          sent_at: 1.hour.ago,
          business: business,
          tenant_customer: customer
        )

        # Create a pending notification using the proper factory method
        pending_notification = PendingSmsNotification.queue_notification(
          notification_type: 'booking_confirmation',
          customer: customer,
          business: business,
          sms_type: 'booking',
          template_data: { customer_name: 'Test', service_name: 'Service' }
        )

        expect(SmsNotificationReplayJob).to receive(:schedule_for_customer).with(customer, business)

        post '/webhooks/twilio/inbound', params: twilio_params
      end

      it 'logs the opt-in processing' do
        # Create a recent SMS message to establish business context
        SmsMessage.create!(
          phone_number: customer.phone,
          content: 'Previous message',
          status: 'sent',
          sent_at: 1.hour.ago,
          business: business,
          tenant_customer: customer
        )

        # Allow for any other log messages but ensure these specific ones are called
        allow(Rails.logger).to receive(:info).and_call_original
        expect(Rails.logger).to receive(:info).with(match(/Processing business-specific opt-in/)).and_call_original
        expect(Rails.logger).to receive(:info).with(match(/Opted in customer #{customer.id}/)).and_call_original

        post '/webhooks/twilio/inbound', params: twilio_params
      end
    end

    context 'when customer replies STOP to opt-out' do
      let(:twilio_params) { super().merge('Body' => 'STOP') }

      before { customer.update!(phone_opt_in: true) }

      it 'processes opt-out successfully' do
        expect {
          post '/webhooks/twilio/inbound', params: twilio_params
        }.to change { customer.reload.phone_opt_in? }.from(true).to(false)
      end

      it 'sends opt-out confirmation message' do
        expect(SmsService).to receive(:send_message).with(
          customer.phone,
          match(/You've been unsubscribed from .+ SMS/),
          hash_including(business_id: business.id, tenant_customer_id: customer.id, auto_reply: true)
        )

        post '/webhooks/twilio/inbound', params: twilio_params
      end
    end

    context 'when customer replies HELP' do
      let(:twilio_params) { super().merge('Body' => 'HELP') }

      it 'sends help response' do
        expect(SmsService).to receive(:send_message).with(
          customer.phone,
          match(/BizBlasts SMS Help/),
          hash_including(business_id: business.id, tenant_customer_id: customer.id, auto_reply: true)
        )

        post '/webhooks/twilio/inbound', params: twilio_params
      end
    end

    context 'when signature verification is enabled' do
      before do
        allow_any_instance_of(Webhooks::TwilioController).to receive(:verify_webhook_signature?).and_return(true)
        allow_any_instance_of(Webhooks::TwilioController).to receive(:valid_signature?).and_return(false)
      end

      it 'rejects requests with invalid signatures' do
        post '/webhooks/twilio/inbound', params: twilio_params

        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)['error']).to eq('Invalid signature')
      end
    end

    context 'error handling in auto-reply' do
      before do
        # Make SmsService.send_message fail
        allow(SmsService).to receive(:send_message).and_raise(StandardError.new('Twilio API error'))
      end

      it 'logs auto-reply failures but continues processing' do
        expect(Rails.logger).to receive(:error).with(match(/Failed to send auto-reply.*Twilio API error/))

        post '/webhooks/twilio/inbound', params: twilio_params

        # Should still opt in the customer despite auto-reply failure
        expect(customer.reload.phone_opt_in?).to be true
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'debugging production issues' do
    it 'provides comprehensive error information' do
      # This test helps debug production issues by testing all components

      # Test business lookup
      controller = Webhooks::TwilioController.new
      found_business = controller.send(:find_business_for_auto_reply, customer.phone)
      expect(found_business).to eq(business)

      # Test SMS service directly
      result = SmsService.send_message(customer.phone, 'Test message', {
        business_id: business.id,
        auto_reply: true
      })
      expect(result[:success]).to be true

      # Test pending notification logic using proper factory method
      pending_notification = PendingSmsNotification.queue_notification(
        notification_type: 'booking_confirmation',
        customer: customer,
        business: business,
        sms_type: 'booking',
        template_data: { customer_name: 'Test', service_name: 'Service' }
      )
      expect(PendingSmsNotification.pending.for_customer(customer).count).to eq(1)
    end
  end
end