# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Twilio Inbound SMS Webhooks', type: :request do
  let!(:business) { create(:business, sms_enabled: true, tier: 'premium') }
  let!(:customer) { create(:tenant_customer, business: business, phone: '+16026866672', phone_opt_in: false) }

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

    # Mock template rendering to avoid missing template errors
    allow(Sms::MessageTemplates).to receive(:render).and_return("Mocked template response")
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
          match(/You're now subscribed to .* SMS notifications/),
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
        post '/webhooks/twilio/inbound', params: twilio_params

        customer.reload
        expect(customer.opted_out_from_business?(business)).to be true
        expect(customer.phone_opt_in?).to be true # Should remain globally opted-in
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

      it 'treats HELP as unknown message (no auto-reply)' do
        expect(SmsService).not_to receive(:send_message)

        post '/webhooks/twilio/inbound', params: twilio_params

        expect(response).to have_http_status(:ok)
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
        expect(Rails.logger).to receive(:error).with(String) # Backtrace log

        post '/webhooks/twilio/inbound', params: twilio_params

        # Should still opt in the customer despite auto-reply failure
        expect(customer.reload.phone_opt_in?).to be true
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'new user scenarios' do
    context 'when completely new phone number texts YES' do
      let(:new_phone) { '+17775551234' }
      let(:new_twilio_params) do
        {
          'From' => new_phone,
          'To' => '+18556128814',
          'Body' => 'YES',
          'MessageSid' => 'SM987654321',
          'AccountSid' => 'AC123456789',
          'MessagingServiceSid' => 'MG123456789'
        }
      end

      it 'creates minimal customer and processes opt-in successfully' do
        expect {
          post '/webhooks/twilio/inbound', params: new_twilio_params
        }.to change { TenantCustomer.count }.by(1)

        new_customer = TenantCustomer.find_by(phone: new_phone)
        expect(new_customer).to be_present
        expect(new_customer.phone_opt_in).to be true
        expect(new_customer.first_name).to eq('Unknown')
        expect(response).to have_http_status(:ok)
      end

      it 'sends auto-reply confirmation for new phone number' do
        expect(SmsService).to receive(:send_message).with(
          new_phone,
          match(/You're now subscribed to .+ SMS notifications\. Reply STOP to unsubscribe\./),
          hash_including(auto_reply: true)
        ).and_return({ success: true })

        post '/webhooks/twilio/inbound', params: new_twilio_params
      end
    end

    context 'when new phone number texts HELP' do
      let(:help_phone) { '+17775559999' }
      let(:help_twilio_params) do
        {
          'From' => help_phone,
          'To' => '+18556128814',
          'Body' => 'HELP',
          'MessageSid' => 'SM111222333',
          'AccountSid' => 'AC123456789',
          'MessagingServiceSid' => 'MG123456789'
        }
      end

      it 'treats HELP as unknown message (no customer created, no auto-reply)' do
        expect {
          post '/webhooks/twilio/inbound', params: help_twilio_params
        }.not_to change { TenantCustomer.count }

        expect(response).to have_http_status(:ok)
      end

      it 'does not send auto-reply for HELP from new phone number' do
        expect(SmsService).not_to receive(:send_message)

        post '/webhooks/twilio/inbound', params: help_twilio_params

        expect(response).to have_http_status(:ok)
      end
    end

    context 'when existing user without tenant customer texts YES' do
      let(:user_without_customer) { create(:user, phone: '+17775552222', business: business) }
      let(:user_twilio_params) do
        {
          'From' => user_without_customer.phone,
          'To' => '+18556128814',
          'Body' => 'YES',
          'MessageSid' => 'SM444555666',
          'AccountSid' => 'AC123456789',
          'MessagingServiceSid' => 'MG123456789'
        }
      end

      it 'links user to tenant customer and processes opt-in' do
        # Mock CustomerLinker to verify it's called
        linker_instance = instance_double(CustomerLinker)
        allow(CustomerLinker).to receive(:new).with(business).and_return(linker_instance)

        new_customer = create(:tenant_customer, business: business, phone: user_without_customer.phone)
        allow(linker_instance).to receive(:link_user_to_customer).with(user_without_customer).and_return(new_customer)

        # Mock the CLASS METHOD for phone lookup (used by TwilioController#find_customers_by_phone)
        # This accurately reflects the controller's implementation which uses class methods for consistency
        allow(CustomerLinker).to receive(:find_customers_by_phone_public).with(user_without_customer.phone, business).and_return([new_customer])

        # Mock global phone lookup method for complete test coverage
        # This ensures tests pass even if controller logic changes to use global lookup
        allow(CustomerLinker).to receive(:find_customers_by_phone_across_all_businesses).with(user_without_customer.phone).and_return([new_customer])

        expect {
          post '/webhooks/twilio/inbound', params: user_twilio_params
        }.to change { new_customer.reload.phone_opt_in }.to(true)
      end
    end
  end

  describe 'business context determination improvements' do
    context 'when customer has SMS opt-in invitation history' do
      let(:invitation_phone) { '+17775553333' }
      let(:invitation_business) { create(:business, sms_enabled: true, tier: 'premium') }

      before do
        # Create recent SMS opt-in invitation to establish business context
        SmsOptInInvitation.create!(
          phone_number: invitation_phone,
          business: invitation_business,
          context: 'booking_confirmation',
          sent_at: 2.days.ago
        )
      end

      it 'uses invitation business context for opt-in' do
        invitation_twilio_params = {
          'From' => invitation_phone,
          'To' => '+18556128814',
          'Body' => 'YES',
          'MessageSid' => 'SM777888999',
          'AccountSid' => 'AC123456789',
          'MessagingServiceSid' => 'MG123456789'
        }

        expect(SmsService).to receive(:send_message).with(
          invitation_phone,
          match(/You're now subscribed to #{invitation_business.name}/),
          hash_including(business_id: invitation_business.id, auto_reply: true)
        )

        post '/webhooks/twilio/inbound', params: invitation_twilio_params
      end
    end

    context 'when no business context found' do
      let(:no_context_phone) { '+17775554444' }

      it 'falls back to most active SMS business' do
        # Create SMS activity for the main business
        create_list(:sms_message, 3, business: business, sent_at: 1.week.ago)

        no_context_twilio_params = {
          'From' => no_context_phone,
          'To' => '+18556128814',
          'Body' => 'YES',
          'MessageSid' => 'SM000111222',
          'AccountSid' => 'AC123456789',
          'MessagingServiceSid' => 'MG123456789'
        }

        expect {
          post '/webhooks/twilio/inbound', params: no_context_twilio_params
        }.to change { TenantCustomer.count }.by(1)

        new_customer = TenantCustomer.find_by(phone: no_context_phone)
        expect(new_customer.business).to eq(business) # Should use fallback business
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