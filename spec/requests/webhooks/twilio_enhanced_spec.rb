require 'rails_helper'

RSpec.describe 'Enhanced Twilio Webhooks', type: :request do
  describe 'POST /webhooks/twilio/inbound' do
    let(:twilio_params) do
      {
        MessageSid: 'SM1234567890abcdef',
        AccountSid: 'AC1234567890abcdef',
        From: '+15551234567',
        To: '+15559876543',
        Body: 'Test message'
      }
    end

    before do
      # Skip signature verification for tests
      allow_any_instance_of(Webhooks::TwilioController).to receive(:verify_webhook_signature?).and_return(false)
    end

    context 'HELP keyword' do
      it 'responds with help message' do
        twilio_params[:Body] = 'HELP'
        
        expect(SmsService).to receive(:send_message).with(
          '+15551234567',
          a_string_including('Help'),
          hash_including(business_id: 1, auto_reply: true)
        )
        
        post '/webhooks/twilio/inbound', params: twilio_params
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['status']).to eq('received')
      end
    end

    context 'STOP keyword' do
      let!(:customer) { create(:tenant_customer, phone: '+15551234567', phone_opt_in: true) }
      
      it 'opts out customer and sends confirmation' do
        twilio_params[:Body] = 'STOP'
        
        expect(SmsService).to receive(:send_message).with(
          '+15551234567',
          a_string_including('unsubscribed'),
          hash_including(business_id: 1, auto_reply: true)
        )
        
        post '/webhooks/twilio/inbound', params: twilio_params
        
        customer.reload
        expect(customer.phone_opt_in?).to be false
        expect(response).to have_http_status(:ok)
      end
    end

    context 'START keyword' do
      let!(:customer) { create(:tenant_customer, phone: '+15551234567', phone_opt_in: false) }
      
      it 'opts in customer and sends confirmation' do
        twilio_params[:Body] = 'START'
        
        expect(SmsService).to receive(:send_message).with(
          '+15551234567',
          a_string_including('opted in'),
          hash_including(business_id: 1, auto_reply: true)
        )
        
        post '/webhooks/twilio/inbound', params: twilio_params
        
        customer.reload
        expect(customer.phone_opt_in?).to be true
        expect(response).to have_http_status(:ok)
      end
    end

    context 'Unknown message' do
      it 'responds with unknown command message for short messages' do
        twilio_params[:Body] = 'xyz'
        
        expect(SmsService).to receive(:send_message).with(
          '+15551234567',
          a_string_including("didn't understand"),
          hash_including(business_id: 1, auto_reply: true)
        )
        
        post '/webhooks/twilio/inbound', params: twilio_params
        expect(response).to have_http_status(:ok)
      end

      it 'does not respond to very long messages' do
        twilio_params[:Body] = 'a' * 101 # Long message
        
        expect(SmsService).not_to receive(:send_message)
        
        post '/webhooks/twilio/inbound', params: twilio_params
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with invalid signature' do
      before do
        allow_any_instance_of(Webhooks::TwilioController).to receive(:verify_webhook_signature?).and_return(true)
        allow_any_instance_of(Webhooks::TwilioController).to receive(:valid_signature?).and_return(false)
      end

      it 'returns forbidden status' do
        post '/webhooks/twilio/inbound', params: twilio_params
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'Phone normalization' do
    let(:controller) { Webhooks::TwilioController.new }

    it 'normalizes various phone formats correctly' do
      # Test different phone number formats
      test_cases = {
        '5551234567' => '+15551234567',
        '+15551234567' => '+15551234567',
        '(555) 123-4567' => '+15551234567',
        '555-123-4567' => '+15551234567',
        '555.123.4567' => '+15551234567',
        '+1-555-123-4567' => '+15551234567'
      }

      test_cases.each do |input, expected|
        result = controller.send(:normalize_phone, input)
        expect(result).to eq(expected), "Expected #{input} to normalize to #{expected}, got #{result}"
      end
    end
  end
end