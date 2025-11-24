require 'rails_helper'

RSpec.describe 'Stripe Webhooks', type: :request do
  include StripeWebhookHelpers
  include ActiveJob::TestHelper

  before do
    ActiveJob::Base.queue_adapter = :test
  end

  it 'enqueues StripeWebhookJob when receiving webhook' do
    data = { 'id' => 'pi_123', 'object' => 'payment_intent' }
    simulate_stripe_webhook('payment_intent.succeeded', data)
    expect(StripeWebhookJob).to have_been_enqueued.with(anything, 'mocked_signature', anything)
  end
end 