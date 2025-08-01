module StripeWebhookHelpers
  def simulate_stripe_webhook(event_type, data)
    # Ensure object has metadata to avoid undefined method errors
    object_data = data.merge('metadata' => {})
    raw_event = { 'type' => event_type, 'data' => { 'object' => object_data } }
    stripe_event = Stripe::Event.construct_from(raw_event)
    # Mock signature verification to return our Stripe::Event
    allow(Stripe::Webhook).to receive(:construct_event).and_return(stripe_event)

    post '/webhooks/stripe',
      params: raw_event.to_json,
      headers: {
        'Content-Type' => 'application/json',
        'Stripe-Signature' => 'mocked_signature'
      }
  end
end 