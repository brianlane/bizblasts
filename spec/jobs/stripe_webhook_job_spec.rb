require 'rails_helper'

RSpec.describe StripeWebhookJob, type: :job do
  include ActiveJob::TestHelper

  let(:payload) { { 'type' => 'payment_intent.succeeded', 'data' => { 'object' => { 'id' => 'pi_test' } } }.to_json }
  let(:sig_header) { 'test_signature' }
  let(:endpoint_secret) { (Rails.application.credentials.stripe || {})[:webhook_secret] || ENV['STRIPE_WEBHOOK_SECRET'] }

  before do
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:info)
  end

  it 'verifies signature and delegates to StripeService' do
    # Stub Stripe::Webhook.construct_event to return a mock event
    mock_event = double('Stripe::Event', data: double(object: { 'id' => 'pi_test' }), type: 'payment_intent.succeeded')
    expect(Stripe::Webhook).to receive(:construct_event).with(payload, sig_header, endpoint_secret).and_return(mock_event)
    expect(StripeService).to receive(:process_webhook).with(mock_event.to_json, anything)

    described_class.perform_now(payload, sig_header)
  end
end 