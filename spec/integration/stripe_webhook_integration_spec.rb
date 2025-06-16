# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Stripe Webhook Integration", type: :request do
  let(:business) { create(:business, subdomain: 'testtenant', hostname: 'testtenant') }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:webhook_secret) { 'whsec_test_secret' }
  let(:valid_signature) { 'valid_signature' }

  before do
    ActsAsTenant.current_tenant = business
    
    # Mock the webhook job since the controller just enqueues it
    allow(StripeWebhookJob).to receive(:perform_later).and_return(true)
    
    # Set up Rails credentials mock
    allow(Rails.application.credentials).to receive(:stripe).and_return({ webhook_secret: webhook_secret })
  end

  describe "POST /webhooks/stripe" do
    let(:webhook_payload) { { type: 'customer.subscription.updated' }.to_json }
    let(:webhook_headers) { { 'Stripe-Signature' => valid_signature } }

    context "webhook acceptance" do
      it "accepts webhook requests and enqueues job" do
        expect(StripeWebhookJob).to receive(:perform_later)

        post '/webhooks/stripe', 
             params: webhook_payload,
             headers: webhook_headers.merge('CONTENT_TYPE' => 'application/json')

        expect(response).to have_http_status(:ok)
      end

      it "returns 200 status for valid webhooks" do
        post '/webhooks/stripe', 
             params: webhook_payload,
             headers: webhook_headers.merge('CONTENT_TYPE' => 'application/json')

        expect(response).to have_http_status(:ok)
      end

      it "handles different webhook types" do
        webhook_types = [
          'customer.subscription.created',
          'customer.subscription.updated', 
          'customer.subscription.deleted',
          'invoice.payment_succeeded',
          'invoice.payment_failed'
        ]

        webhook_types.each do |webhook_type|
          payload = { type: webhook_type }.to_json
          
          post '/webhooks/stripe', 
               params: payload,
               headers: webhook_headers.merge('CONTENT_TYPE' => 'application/json')

          expect(response).to have_http_status(:ok)
        end
      end

      it "enqueues job with correct parameters" do
        expect(StripeWebhookJob).to receive(:perform_later).with(
          webhook_payload,
          valid_signature
        )

        post '/webhooks/stripe', 
             params: webhook_payload,
             headers: webhook_headers.merge('CONTENT_TYPE' => 'application/json')
      end
    end

    context "error handling" do
      it "handles malformed JSON gracefully" do
        invalid_payload = "invalid json"
        
        # Mock the request body to return malformed JSON
        allow_any_instance_of(ActionDispatch::Request).to receive(:body).and_return(
          StringIO.new(invalid_payload)
        )
        
        post '/webhooks/stripe', 
             headers: webhook_headers

        expect(response).to have_http_status(:ok)
      end

      it "handles missing headers" do
        post '/webhooks/stripe', 
             params: webhook_payload

        expect(response).to have_http_status(:ok)
      end

      it "handles empty payload" do
        post '/webhooks/stripe', 
             params: "",
             headers: webhook_headers.merge('CONTENT_TYPE' => 'application/json')

        expect(response).to have_http_status(:ok)
      end
    end
  end
end 