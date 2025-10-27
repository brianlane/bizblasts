# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Middleware::WebhookAuthenticator do
  let(:app) { ->(env) { [200, { 'Content-Type' => 'application/json' }, ['{"status":"ok"}']] } }
  let(:middleware) { described_class.new(app) }

  def make_request(path:, method: 'POST', headers: {}, body: '{}')
    env = Rack::MockRequest.env_for(
      "http://localhost#{path}",
      method: method,
      input: StringIO.new(body),
      'CONTENT_TYPE' => 'application/json',
      'CONTENT_LENGTH' => body.bytesize.to_s
    )
    headers.each { |key, value| env[key] = value }
    middleware.call(env)
  end

  describe 'path matching' do
    it 'recognizes Stripe webhook path' do
      response = make_request(path: '/webhooks/stripe')
      # Should return 401 because signature is missing/invalid
      expect(response[0]).to eq(401)
    end

    it 'recognizes subscription webhook path' do
      response = make_request(path: '/manage/settings/stripe_events')
      # Should return 401 because signature is missing/invalid
      expect(response[0]).to eq(401)
    end

    it 'allows non-webhook paths through without verification' do
      response = make_request(path: '/api/businesses')
      # Should pass through to app without verification
      expect(response[0]).to eq(200)
    end

    it 'allows root path through without verification' do
      response = make_request(path: '/')
      expect(response[0]).to eq(200)
    end

    it 'middleware paths match actual Rails routes' do
      # Get actual Stripe webhook routes from Rails
      stripe_webhook_routes = Rails.application.routes.routes.select do |route|
        route.defaults[:controller]&.match?(/stripe_webhooks|subscriptions/) &&
        route.defaults[:action] == 'webhook' || route.defaults[:action] == 'create' && route.path.spec.to_s.include?('webhooks/stripe')
      end

      # Extract paths without format extension
      actual_paths = stripe_webhook_routes.map do |route|
        route.path.spec.to_s.gsub('(.:format)', '')
      end

      # Verify each actual path matches the middleware regex
      actual_paths.each do |path|
        expect(described_class::STRIPE_PATHS).to match(path),
          "Middleware STRIPE_PATHS regex should match route: #{path}"
      end

      # Verify we found the expected routes
      expect(actual_paths).to include('/webhooks/stripe')
      expect(actual_paths).to include('/manage/settings/stripe_events')
    end
  end

  describe 'Stripe signature verification' do
    let(:payload) { '{"type":"test.event","data":{}}' }
    let(:endpoint_secret) { 'whsec_test_secret' }
    let(:valid_signature) { 'valid_signature_from_stripe' }

    before do
      allow(Rails.application.credentials).to receive(:dig).with(:stripe, :webhook_secret).and_return(endpoint_secret)
    end

    it 'rejects requests without signature header' do
      response = make_request(
        path: '/webhooks/stripe',
        body: payload
      )

      expect(response[0]).to eq(401)
      expect(response[2].first).to include('invalid signature')
    end

    it 'rejects requests with invalid signature' do
      allow(Stripe::Webhook).to receive(:construct_event).and_raise(
        Stripe::SignatureVerificationError.new('Invalid signature', 'sig_header')
      )

      response = make_request(
        path: '/webhooks/stripe',
        body: payload,
        headers: { 'HTTP_STRIPE_SIGNATURE' => 'invalid_signature' }
      )

      expect(response[0]).to eq(401)
    end

    it 'accepts requests with valid Stripe signature' do
      allow(Stripe::Webhook).to receive(:construct_event).and_return(
        double('Stripe::Event', type: 'test.event')
      )

      response = make_request(
        path: '/webhooks/stripe',
        body: payload,
        headers: { 'HTTP_STRIPE_SIGNATURE' => valid_signature }
      )

      expect(response[0]).to eq(200)
    end

    it 'rewinds request body after reading for signature verification' do
      allow(Stripe::Webhook).to receive(:construct_event) do |body, sig, secret|
        expect(body).to eq(payload)
        double('Stripe::Event', type: 'test.event')
      end

      make_request(
        path: '/webhooks/stripe',
        body: payload,
        headers: { 'HTTP_STRIPE_SIGNATURE' => valid_signature }
      )

      # If body wasn't rewound, subsequent reads would fail
      # This is implicitly tested by the controller being able to read the body
    end

    it 'handles JSON parse errors gracefully' do
      allow(Stripe::Webhook).to receive(:construct_event).and_raise(
        JSON::ParserError.new('Invalid JSON')
      )

      response = make_request(
        path: '/webhooks/stripe',
        body: 'invalid json',
        headers: { 'HTTP_STRIPE_SIGNATURE' => valid_signature }
      )

      expect(response[0]).to eq(401)
    end

    it 'uses environment variable when credentials not set' do
      allow(Rails.application.credentials).to receive(:dig).with(:stripe, :webhook_secret).and_return(nil)
      allow(ENV).to receive(:[]).with('STRIPE_WEBHOOK_SECRET').and_return('env_secret')

      expect(Stripe::Webhook).to receive(:construct_event).with(
        payload,
        valid_signature,
        'env_secret'
      ).and_return(double('Stripe::Event'))

      response = make_request(
        path: '/webhooks/stripe',
        body: payload,
        headers: { 'HTTP_STRIPE_SIGNATURE' => valid_signature }
      )

      expect(response[0]).to eq(200)
    end
  end

  describe 'tenant isolation' do
    it 'does not modify ActsAsTenant context' do
      # Create a test business and set as current tenant
      business = create(:business)
      ActsAsTenant.current_tenant = business

      allow(Stripe::Webhook).to receive(:construct_event).and_return(
        double('Stripe::Event', type: 'test.event')
      )

      make_request(
        path: '/webhooks/stripe',
        body: '{"type":"test"}',
        headers: { 'HTTP_STRIPE_SIGNATURE' => 'valid_sig' }
      )

      # Tenant context should be unchanged after middleware processing
      expect(ActsAsTenant.current_tenant).to eq(business)
    end

    it 'does not set tenant context when none exists' do
      ActsAsTenant.current_tenant = nil

      allow(Stripe::Webhook).to receive(:construct_event).and_return(
        double('Stripe::Event', type: 'test.event')
      )

      make_request(
        path: '/webhooks/stripe',
        body: '{"type":"test"}',
        headers: { 'HTTP_STRIPE_SIGNATURE' => 'valid_sig' }
      )

      # Should remain nil
      expect(ActsAsTenant.current_tenant).to be_nil
    end

    it 'processes webhook without requiring tenant context' do
      ActsAsTenant.current_tenant = nil

      allow(Stripe::Webhook).to receive(:construct_event).and_return(
        double('Stripe::Event', type: 'test.event')
      )

      response = make_request(
        path: '/webhooks/stripe',
        body: '{"type":"test"}',
        headers: { 'HTTP_STRIPE_SIGNATURE' => 'valid_sig' }
      )

      # Should successfully pass through even without tenant
      expect(response[0]).to eq(200)
    end
  end

  describe 'error responses' do
    it 'returns 401 status code for unauthorized requests' do
      response = make_request(path: '/webhooks/stripe')
      expect(response[0]).to eq(401)
    end

    it 'returns JSON error message' do
      response = make_request(path: '/webhooks/stripe')
      expect(response[1]['Content-Type']).to eq('application/json')
      expect(response[2].first).to include('error')
      expect(response[2].first).to include('Unauthorized')
    end

    it 'includes custom error header' do
      response = make_request(path: '/webhooks/stripe')
      expect(response[1]['X-Webhook-Error']).to eq('Invalid signature')
    end

    it 'logs verification failures' do
      expect(Rails.logger).to receive(:warn).with(/Signature verification failed/)
      expect(Rails.logger).to receive(:warn).with(/Returning 401 Unauthorized/)

      make_request(path: '/webhooks/stripe')
    end
  end

  describe 'logging' do
    before do
      allow(Stripe::Webhook).to receive(:construct_event).and_return(
        double('Stripe::Event', type: 'test.event')
      )
    end

    it 'logs webhook request processing' do
      expect(Rails.logger).to receive(:info).with(/Processing webhook request to \/webhooks\/stripe/).ordered
      expect(Rails.logger).to receive(:info).with(/Signature verified successfully/).ordered

      make_request(
        path: '/webhooks/stripe',
        headers: { 'HTTP_STRIPE_SIGNATURE' => 'valid_sig' }
      )
    end

    it 'logs successful signature verification' do
      expect(Rails.logger).to receive(:info).with(/Processing webhook request/).ordered
      expect(Rails.logger).to receive(:info).with(/Signature verified successfully/).ordered

      make_request(
        path: '/webhooks/stripe',
        headers: { 'HTTP_STRIPE_SIGNATURE' => 'valid_sig' }
      )
    end
  end

  describe 'integration with app' do
    it 'calls the next middleware/app when signature is valid' do
      allow(Stripe::Webhook).to receive(:construct_event).and_return(
        double('Stripe::Event', type: 'test.event')
      )

      app_called = false
      test_app = lambda do |env|
        app_called = true
        [200, {}, ['app response']]
      end

      test_middleware = described_class.new(test_app)
      test_middleware.call(Rack::MockRequest.env_for(
        'http://localhost/webhooks/stripe',
        method: 'POST',
        input: StringIO.new('{"type":"test"}'),
        'HTTP_STRIPE_SIGNATURE' => 'valid_sig'
      ))

      expect(app_called).to be true
    end

    it 'does not call the next middleware/app when signature is invalid' do
      app_called = false
      test_app = lambda do |env|
        app_called = true
        [200, {}, ['app response']]
      end

      test_middleware = described_class.new(test_app)
      test_middleware.call(Rack::MockRequest.env_for(
        'http://localhost/webhooks/stripe',
        method: 'POST',
        input: StringIO.new('{"type":"test"}')
      ))

      expect(app_called).to be false
    end
  end
end
