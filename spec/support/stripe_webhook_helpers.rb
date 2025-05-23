module StripeWebhookHelpers
  def simulate_stripe_webhook(event_type, data)
    event = { 'type' => event_type, 'data' => { 'object' => data } }
    # Mock signature verification to return our event
    allow(Stripe::Webhook).to receive(:construct_event).and_return(event)

    post '/webhooks/stripe',
      params: event.to_json,
      headers: {
        'Content-Type' => 'application/json',
        'Stripe-Signature' => 'mocked_signature'
      }
  end
end 