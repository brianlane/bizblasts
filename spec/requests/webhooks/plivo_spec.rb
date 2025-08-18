# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Plivo Webhooks', type: :request do
  let!(:tenant) { create(:business) }
  let!(:customer) { create(:tenant_customer, business: tenant, phone: "+15558675309") }
  let!(:sms_message) { create(:sms_message, :sent, external_id: "plivo-uuid-123", tenant_customer: customer) }

  around do |example|
    ActsAsTenant.with_tenant(tenant) do
      example.run
    end
  end


  describe 'POST /webhooks/plivo' do
    let(:valid_params) do
      {
        MessageUUID: "plivo-uuid-123",
        Status: "delivered",
        MessageState: "delivered",
        TotalRate: "0.00350",
        TotalAmount: "0.00350",
        Units: 1,
        MCC: "310",
        MNC: "004",
        ErrorCode: ""
      }
    end

    context 'with valid Plivo webhook data' do
      it 'processes delivery receipt successfully' do
        allow(SmsService).to receive(:process_webhook).and_return(
          { success: true, status: "delivered" }
        )

        post '/webhooks/plivo', params: valid_params
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['status']).to eq('success')
        expect(json_response['message']).to eq('Webhook processed')
      end

      it 'actually processes the webhook through SmsService' do
        post '/webhooks/plivo', params: valid_params
        
        expect(response).to have_http_status(:ok)
        expect(sms_message.reload.status).to eq('delivered')
        expect(sms_message.delivered_at).to be_present
      end
    end

    context 'when webhook processing fails' do
      let(:invalid_params) do
        valid_params.merge(MessageUUID: "plivo-uuid-nonexistent")
      end

      it 'returns unprocessable entity status' do
        post '/webhooks/plivo', params: invalid_params
        
        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include("Message not found")
      end
    end

    context 'when signature verification is disabled (development)' do
      before do
        allow(Rails.env).to receive(:production?).and_return(false)
        allow(ENV).to receive(:[]).with('PLIVO_VERIFY_SIGNATURES').and_return(nil)
      end

      it 'processes webhook without signature check' do
        post '/webhooks/plivo', params: valid_params
        expect(response).to have_http_status(:ok)
      end
    end

    context 'CSRF protection' do
      it 'skips CSRF verification for webhook endpoints' do
        # This test ensures webhook endpoints work without CSRF tokens
        expect { post '/webhooks/plivo', params: valid_params }.not_to raise_error
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with missing required parameters' do
      it 'handles missing MessageUUID' do
        params_without_uuid = valid_params.except(:MessageUUID)
        post '/webhooks/plivo', params: params_without_uuid
        
        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Missing MessageUUID in webhook')
      end

      it 'handles missing Status' do
        params_without_status = valid_params.except(:Status)
        post '/webhooks/plivo', params: params_without_status
        
        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Missing Status in webhook')
      end
    end
  end
end