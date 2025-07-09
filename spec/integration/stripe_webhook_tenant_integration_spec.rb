# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Stripe Webhook Tenant Integration", type: :request do
  let!(:business) { create(:business, subdomain: 'testtenant', hostname: 'testtenant', stripe_account_id: 'acct_test123') }
  let!(:tenant_customer) { create(:tenant_customer, business: business, stripe_customer_id: 'cus_test123') }
  let!(:invoice) { create(:invoice, business: business, tenant_customer: tenant_customer, status: :pending) }
  let!(:payment) { create(:payment, business: business, invoice: invoice, tenant_customer: tenant_customer, stripe_payment_intent_id: 'pi_test123', status: :pending) }
  
  let(:webhook_secret) { 'whsec_test_secret' }
  let(:valid_signature) { 'valid_signature' }

  def build_event_json(type, overrides = {})
    base_event = {
      id: "evt_#{SecureRandom.hex(8)}",
      type: type,
      account: business.stripe_account_id,
      data: { object: {} }
    }

    case type
    when 'payment_intent.succeeded'
      base_event[:data][:object] = {
        id: 'pi_test123',
        status: 'succeeded',
        metadata: {
          business_id: business.id.to_s,
          invoice_id: invoice.id.to_s
        },
        charges: { data: [{ payment_method_details: { type: 'card' } }] }
      }.merge(overrides)
    when 'invoice.payment_succeeded'
      base_event[:data][:object] = {
        id: "in_#{SecureRandom.hex(8)}",
        subscription: "sub_#{SecureRandom.hex(8)}",
        metadata: {}
      }.merge(overrides)
    end

    base_event.to_json
  end

  before do
    # Set up Rails credentials mock
    allow(Rails.application.credentials).to receive(:stripe).and_return({ webhook_secret: webhook_secret })
  end

  describe "POST /webhooks/stripe" do
    let(:payload) { build_event_json('payment_intent.succeeded') }
    let(:event) { Stripe::Event.construct_from(JSON.parse(payload)) }

    before do
      allow(Stripe::Webhook).to receive(:construct_event).and_return(event)
    end

    it "extracts tenant context from webhook metadata" do
      expect(StripeWebhookJob).to receive(:perform_later).with(payload, valid_signature, business.id)
      post '/webhooks/stripe', params: payload, headers: { "Stripe-Signature" => valid_signature, "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:ok)
    end

    it "processes payment with correct tenant context" do
      ActiveJob::Base.queue_adapter = :test
      expect {
        post '/webhooks/stripe', params: payload, headers: { "Stripe-Signature" => valid_signature, "CONTENT_TYPE" => "application/json" }
      }.to have_enqueued_job(StripeWebhookJob).with(payload, valid_signature, business.id)

      # Perform the job to check for side-effects
      perform_enqueued_jobs
      payment.reload
      invoice.reload

      expect(payment.status).to eq('completed')
      expect(invoice.status).to eq('paid')
    end

    context "when webhook has no tenant context" do
      let(:payload) do
        event_data = JSON.parse(build_event_json('payment_intent.succeeded', { id: 'pi_no_context' }))
        event_data['data']['object']['metadata'] = {} # Explicitly clear metadata
        event_data.delete('account') # Remove account to prevent fallback lookup
        event_data.to_json
      end

      it "falls back to unscoped search" do
        # In a real scenario, the payment would still be found by its unscoped ID
        payment_no_context = Payment.unscoped.find_by!(stripe_payment_intent_id: 'pi_test123')
        payment_no_context.update!(stripe_payment_intent_id: 'pi_no_context')

        # Use the test queue adapter to check for side effects
        ActiveJob::Base.queue_adapter = :test

        post '/webhooks/stripe', params: payload, headers: { "Stripe-Signature" => valid_signature, "CONTENT_TYPE" => "application/json" }
        expect(response).to have_http_status(:ok)

        # Verify the job was enqueued with nil tenant_id
        expect(StripeWebhookJob).to have_been_enqueued.with(payload, valid_signature, nil)

        # Now, perform the job and check the outcome
        perform_enqueued_jobs

        payment_no_context.reload
        expect(payment_no_context.status).to eq('completed')
      end
    end
  end

  describe "tenant context extraction logic" do
    let(:controller) { StripeWebhooksController.new }

    it "extracts business_id from payment_intent metadata" do
      payload = build_event_json('payment_intent.succeeded')
      event = Stripe::Event.construct_from(JSON.parse(payload))
      expect(controller.send(:find_business_id_from_event, event)).to eq(business.id.to_s)
    end

    it "finds business through customer subscription on invoice event" do
      subscription = create(:customer_subscription, business: business, stripe_subscription_id: 'sub_test123')
      payload = build_event_json('invoice.payment_succeeded', { subscription: subscription.stripe_subscription_id })
      event = Stripe::Event.construct_from(JSON.parse(payload))
      expect(controller.send(:find_business_id_from_event, event)).to eq(business.id)
    end
  end
end 