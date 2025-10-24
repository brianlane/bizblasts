# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Webhooks::Twilio Inbound Keywords', type: :request do
  let(:business) { create(:business, sms_enabled: true, tier: 'premium') }
  let(:customer) { create(:tenant_customer, business: business, phone: '+15558675309', phone_opt_in: false, skip_notification_email: true) }

  # Mock Twilio for auto-reply sending
  before do
    twilio_client = instance_double(Twilio::REST::Client)
    twilio_messages = double("Messages")
    twilio_response = double("MessageResource", sid: "twilio-sid-#{SecureRandom.hex(4)}")

    allow(Twilio::REST::Client).to receive(:new).and_return(twilio_client)
    allow(twilio_client).to receive(:messages).and_return(twilio_messages)
    allow(twilio_messages).to receive(:create).and_return(twilio_response)

    allow(Rails.application.config).to receive(:sms_enabled).and_return(true)
  end

  around do |example|
    ActsAsTenant.with_tenant(business) do
      example.run
    end
  end

  describe 'HELP keyword' do
    let(:help_params) do
      {
        From: customer.phone,
        Body: 'HELP',
        MessageSid: "twilio-sid-help-#{SecureRandom.hex(4)}"
      }
    end

    it 'responds with help message' do
      expect(Sms::MessageTemplates).to receive(:render).with('system.help_response', anything).and_return('Help message')
      post '/webhooks/twilio/inbound', params: help_params
      expect(response).to have_http_status(:ok)
    end

    it 'logs HELP keyword received' do
      allow(Rails.logger).to receive(:info) # Allow other logs first
      expect(Rails.logger).to receive(:info).with(a_string_matching(/Received Twilio inbound SMS/))
      expect(Rails.logger).to receive(:info).with(SecureLogger.sanitize_message("Inbound SMS from #{customer.phone}: HELP"))
      expect(Rails.logger).to receive(:info).with(SecureLogger.sanitize_message("HELP keyword received from #{customer.phone}"))

      post '/webhooks/twilio/inbound', params: help_params
    end

    it 'does not change opt-in status' do
      expect {
        post '/webhooks/twilio/inbound', params: help_params
      }.not_to change { customer.reload.phone_opt_in? }
    end

    it 'sends auto-reply with help information' do
      expect(SmsService).to receive(:send_message).with(
        customer.phone,
        anything,
        hash_including(auto_reply: true)
      )
      post '/webhooks/twilio/inbound', params: help_params
    end

    it 'is case insensitive' do
      lowercase_params = help_params.merge(Body: 'help')

      expect(Rails.logger).to receive(:info).with(SecureLogger.sanitize_message("HELP keyword received from #{customer.phone}"))
      allow(Rails.logger).to receive(:info)

      post '/webhooks/twilio/inbound', params: lowercase_params
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'STOP/CANCEL/UNSUBSCRIBE keywords' do
    let(:stop_params) do
      {
        From: customer.phone,
        Body: 'STOP',
        MessageSid: "twilio-sid-stop-#{SecureRandom.hex(4)}"
      }
    end

    context 'with STOP keyword' do
      it 'processes opt-out' do
        customer.update!(phone_opt_in: true, phone_opt_in_at: Time.current)

        expect(Rails.logger).to receive(:info).with(SecureLogger.sanitize_message("STOP keyword received from #{customer.phone} - processing opt-out"))
        allow(Rails.logger).to receive(:info)

        post '/webhooks/twilio/inbound', params: stop_params
        expect(response).to have_http_status(:ok)
      end

      it 'returns success response' do
        post '/webhooks/twilio/inbound', params: stop_params
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to include('status' => 'received')
      end

      it 'is case insensitive' do
        lowercase_params = stop_params.merge(Body: 'stop')

        expect(Rails.logger).to receive(:info).with(SecureLogger.sanitize_message("STOP keyword received from #{customer.phone} - processing opt-out"))
        allow(Rails.logger).to receive(:info)

        post '/webhooks/twilio/inbound', params: lowercase_params
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with CANCEL keyword' do
      let(:cancel_params) { stop_params.merge(Body: 'CANCEL') }

      it 'treats CANCEL same as STOP' do
        expect(Rails.logger).to receive(:info).with(SecureLogger.sanitize_message("STOP keyword received from #{customer.phone} - processing opt-out"))
        allow(Rails.logger).to receive(:info)

        post '/webhooks/twilio/inbound', params: cancel_params
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with UNSUBSCRIBE keyword' do
      let(:unsubscribe_params) { stop_params.merge(Body: 'UNSUBSCRIBE') }

      it 'treats UNSUBSCRIBE same as STOP' do
        expect(Rails.logger).to receive(:info).with(SecureLogger.sanitize_message("STOP keyword received from #{customer.phone} - processing opt-out"))
        allow(Rails.logger).to receive(:info)

        post '/webhooks/twilio/inbound', params: unsubscribe_params
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when customer has pending SMS invitations' do
      let!(:invitation) { create(:sms_opt_in_invitation, phone_number: customer.phone, business: business, tenant_customer: customer, context: 'booking_confirmation', sent_at: 1.hour.ago) }

      it 'does not record invitation response for STOP' do
        expect {
          post '/webhooks/twilio/inbound', params: stop_params
        }.not_to change { invitation.reload.responded_at }
      end
    end
  end

  describe 'START/SUBSCRIBE/YES keywords' do
    let(:start_params) do
      {
        From: customer.phone,
        Body: 'START',
        MessageSid: "twilio-sid-start-#{SecureRandom.hex(4)}"
      }
    end

    context 'with START keyword' do
      it 'processes opt-in' do
        expect(Rails.logger).to receive(:info).with(SecureLogger.sanitize_message("START keyword received from #{customer.phone} - processing opt-in"))
        allow(Rails.logger).to receive(:info)

        post '/webhooks/twilio/inbound', params: start_params
        expect(response).to have_http_status(:ok)
      end

      it 'returns success response' do
        post '/webhooks/twilio/inbound', params: start_params
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to include('status' => 'received')
      end

      it 'is case insensitive' do
        lowercase_params = start_params.merge(Body: 'start')

        expect(Rails.logger).to receive(:info).with(SecureLogger.sanitize_message("START keyword received from #{customer.phone} - processing opt-in"))
        allow(Rails.logger).to receive(:info)

        post '/webhooks/twilio/inbound', params: lowercase_params
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with SUBSCRIBE keyword' do
      let(:subscribe_params) { start_params.merge(Body: 'SUBSCRIBE') }

      it 'treats SUBSCRIBE same as START' do
        expect(Rails.logger).to receive(:info).with(SecureLogger.sanitize_message("START keyword received from #{customer.phone} - processing opt-in"))
        allow(Rails.logger).to receive(:info)

        post '/webhooks/twilio/inbound', params: subscribe_params
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with YES keyword' do
      let(:yes_params) { start_params.merge(Body: 'YES') }

      it 'treats YES same as START' do
        expect(Rails.logger).to receive(:info).with(SecureLogger.sanitize_message("START keyword received from #{customer.phone} - processing opt-in"))
        allow(Rails.logger).to receive(:info)

        post '/webhooks/twilio/inbound', params: yes_params
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when customer has pending SMS invitations' do
      let!(:invitation) { create(:sms_opt_in_invitation, phone_number: customer.phone, business: business, tenant_customer: customer, context: 'booking_confirmation', sent_at: 1.hour.ago) }

      it 'records invitation response' do
        post '/webhooks/twilio/inbound', params: start_params.merge(Body: 'YES')

        expect(invitation.reload.responded_at).to be_present
        expect(invitation.response).to eq('YES')
        expect(invitation.successful_opt_in).to be true
      end
    end

    context 'when there are pending notifications' do
      let!(:pending_notification) { create(:pending_sms_notification, business: business, tenant_customer: customer) }

      it 'schedules notification replay' do
        expect(SmsNotificationReplayJob).to receive(:schedule_for_customer)
        post '/webhooks/twilio/inbound', params: start_params
      end
    end
  end

  describe 'CONFIRM keyword' do
    let(:confirm_params) do
      {
        From: customer.phone,
        Body: 'CONFIRM',
        MessageSid: "twilio-sid-confirm-#{SecureRandom.hex(4)}"
      }
    end

    it 'logs CONFIRM keyword received' do
      allow(Rails.logger).to receive(:info) # Allow other logs first
      expect(Rails.logger).to receive(:info).with(a_string_matching(/Received Twilio inbound SMS/))
      expect(Rails.logger).to receive(:info).with(SecureLogger.sanitize_message("Inbound SMS from #{customer.phone}: CONFIRM"))
      expect(Rails.logger).to receive(:info).with(SecureLogger.sanitize_message("CONFIRM keyword received from #{customer.phone}"))

      post '/webhooks/twilio/inbound', params: confirm_params
    end

    it 'returns success response' do
      post '/webhooks/twilio/inbound', params: confirm_params
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include('status' => 'received')
    end

    it 'is case insensitive' do
      lowercase_params = confirm_params.merge(Body: 'confirm')

      expect(Rails.logger).to receive(:info).with(SecureLogger.sanitize_message("CONFIRM keyword received from #{customer.phone}"))
      allow(Rails.logger).to receive(:info)

      post '/webhooks/twilio/inbound', params: lowercase_params
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'Unknown messages' do
    let(:unknown_params) do
      {
        From: customer.phone,
        Body: 'Hello, I have a question about my appointment',
        MessageSid: "twilio-sid-unknown-#{SecureRandom.hex(4)}"
      }
    end

    it 'logs unknown message' do
      allow(Rails.logger).to receive(:info) # Allow other logs first
      expect(Rails.logger).to receive(:info).with(a_string_matching(/Received Twilio inbound SMS/))
      expect(Rails.logger).to receive(:info).with(SecureLogger.sanitize_message("Inbound SMS from #{customer.phone}: Hello, I have a question about my appointment"))
      expect(Rails.logger).to receive(:info).with(SecureLogger.sanitize_message("Other inbound message from #{customer.phone}: Hello, I have a question about my appointment"))

      post '/webhooks/twilio/inbound', params: unknown_params
    end

    it 'sends unknown command response for short messages' do
      short_message_params = unknown_params.merge(Body: 'Hello')

      expect(Sms::MessageTemplates).to receive(:render).with('system.unknown_command').and_return('Unknown command message')
      expect(SmsService).to receive(:send_message).with(
        customer.phone,
        'Unknown command message',
        hash_including(auto_reply: true)
      )

      post '/webhooks/twilio/inbound', params: short_message_params
    end

    it 'does not send response for long messages' do
      long_message_params = unknown_params.merge(Body: 'a' * 101)

      expect(SmsService).not_to receive(:send_message)
      post '/webhooks/twilio/inbound', params: long_message_params
    end

    it 'returns success response' do
      post '/webhooks/twilio/inbound', params: unknown_params
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include('status' => 'received')
    end
  end

  describe 'Edge cases' do
    context 'with empty message body' do
      let(:empty_params) do
        {
          From: customer.phone,
          Body: '',
          MessageSid: "twilio-sid-empty-#{SecureRandom.hex(4)}"
        }
      end

      it 'handles empty message gracefully' do
        post '/webhooks/twilio/inbound', params: empty_params
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with whitespace-only message' do
      let(:whitespace_params) do
        {
          From: customer.phone,
          Body: '   ',
          MessageSid: "twilio-sid-whitespace-#{SecureRandom.hex(4)}"
        }
      end

      it 'handles whitespace message gracefully' do
        post '/webhooks/twilio/inbound', params: whitespace_params
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with keyword plus extra text' do
      let(:keyword_with_text_params) do
        {
          From: customer.phone,
          Body: 'STOP please',
          MessageSid: "twilio-sid-extra-#{SecureRandom.hex(4)}"
        }
      end

      it 'does not recognize keyword with extra text' do
        expect(Rails.logger).not_to receive(:info).with(/STOP keyword received/)
        allow(Rails.logger).to receive(:info)

        post '/webhooks/twilio/inbound', params: keyword_with_text_params
      end
    end

    context 'without customer record' do
      let(:new_phone) { '+15559876543' }
      let(:new_customer_params) do
        {
          From: new_phone,
          Body: 'HELP',
          MessageSid: "twilio-sid-new-#{SecureRandom.hex(4)}"
        }
      end

      it 'creates minimal customer record' do
        expect {
          post '/webhooks/twilio/inbound', params: new_customer_params
        }.to change(TenantCustomer, :count).by(1)
      end

      it 'processes keyword normally' do
        post '/webhooks/twilio/inbound', params: new_customer_params
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'Business context determination' do
    let(:other_business) { create(:business, sms_enabled: true, tier: 'premium') }
    let!(:sms_from_business) { create(:sms_message, business: business, phone_number: customer.phone, sent_at: 1.hour.ago) }

    context 'when recent SMS activity exists' do
      it 'determines correct business context from recent SMS' do
        start_params = {
          From: customer.phone,
          Body: 'YES',
          MessageSid: "twilio-sid-yes-#{SecureRandom.hex(4)}"
        }

        # Should determine business from recent SMS
        post '/webhooks/twilio/inbound', params: start_params
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when opt-in invitation exists' do
      let!(:invitation) { create(:sms_opt_in_invitation, phone_number: customer.phone, business: business, tenant_customer: customer, context: 'booking_confirmation', sent_at: 30.minutes.ago) }

      it 'uses invitation business context' do
        yes_params = {
          From: customer.phone,
          Body: 'YES',
          MessageSid: "twilio-sid-yes-context-#{SecureRandom.hex(4)}"
        }

        post '/webhooks/twilio/inbound', params: yes_params
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'Signature verification' do
    context 'in production environment' do
      before do
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      context 'with invalid signature' do
        before do
          allow_any_instance_of(Webhooks::TwilioController).to receive(:verify_webhook_signature?).and_return(true)
          allow_any_instance_of(Webhooks::TwilioController).to receive(:valid_signature?).and_return(false)
        end

        it 'rejects request with invalid signature' do
          post '/webhooks/twilio/inbound', params: { From: customer.phone, Body: 'HELP', MessageSid: 'test-sid' }
          expect(response).to have_http_status(:forbidden)
        end
      end
    end
  end
end
