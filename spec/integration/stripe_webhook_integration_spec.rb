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

    # Set up Rails credentials mock (middleware uses .dig)
    allow(Rails.application.credentials).to receive(:dig).with(:stripe, :webhook_secret).and_return(webhook_secret)

    # Mock Stripe signature verification (middleware layer)
    allow(Stripe::Webhook).to receive(:construct_event).and_return(
      double('Stripe::Event',
        type: 'test.event',
        account: nil,
        data: double(object: double(metadata: {}))
      )
    )
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
          valid_signature,
          anything
        )

        post '/webhooks/stripe', 
             params: webhook_payload,
             headers: webhook_headers.merge('CONTENT_TYPE' => 'application/json')
      end
    end

    context "error handling" do
      it "handles malformed JSON gracefully" do
        invalid_payload = "invalid json"

        # Mock Stripe to raise JSON parse error
        allow(Stripe::Webhook).to receive(:construct_event).and_raise(
          JSON::ParserError.new('Invalid JSON')
        )

        post '/webhooks/stripe',
             params: invalid_payload,
             headers: webhook_headers.merge('CONTENT_TYPE' => 'application/json')

        # Middleware rejects with 401 when signature verification fails
        expect(response).to have_http_status(:unauthorized)
      end

      it "handles missing headers" do
        post '/webhooks/stripe',
             params: webhook_payload,
             headers: { 'CONTENT_TYPE' => 'application/json' }

        # Middleware rejects with 401 when signature header is missing
        expect(response).to have_http_status(:unauthorized)
      end

      it "handles empty payload" do
        post '/webhooks/stripe',
             params: "",
             headers: webhook_headers.merge('CONTENT_TYPE' => 'application/json')

        # Empty payload is accepted by middleware but controller returns OK
        expect(response).to have_http_status(:ok)
      end
    end
  end
end 