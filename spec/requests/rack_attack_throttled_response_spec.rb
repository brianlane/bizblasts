# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rack::Attack throttled responses' do
  describe 'throttled_responder' do
    it 'returns 429 with Retry-After when rack-attack passes a Request' do
      env = Rack::MockRequest.env_for('/contact', 'REMOTE_ADDR' => '203.0.113.8')
      env['rack.attack.match_data'] = { period: 60, epoch_time: 30, limit: 100, count: 101 }
      status, headers, body = Rack::Attack.throttled_responder.call(Rack::Attack::Request.new(env))

      expect(status).to eq(429)
      expect(headers['Content-Type']).to eq('application/json')
      expect(headers['Retry-After']).to eq('30')
      expect(JSON.parse(body.join)).to eq('error' => 'Rate limit exceeded. Please try again later.')
    end

    it 'returns 429 instead of raising when the responder input is not a Request' do
      status, headers, body = Rack::Attack.throttled_responder.call(Object.new)

      expect(status).to eq(429)
      expect(body.join).to include('Rate limit exceeded')
      expect(headers['Retry-After']).to be_nil
    end

    it 'fails open to a plain 429 when match data cannot be read' do
      request = Rack::Attack::Request.new(Rack::MockRequest.env_for('/contact'))
      allow(request).to receive(:env).and_raise(NoMethodError, "undefined method '[]'")

      status, headers, = Rack::Attack.throttled_responder.call(request)

      expect(status).to eq(429)
      expect(headers['Content-Type']).to eq('text/plain')
    end
  end

  describe 'per-visitor throttling' do
    let(:stack) do
      Rack::Builder.new do
        use Middleware::LocalProxyClientIp
        use Rack::Attack
        run ->(_env) { [200, { 'content-type' => 'text/plain' }, ['ok']] }
      end
    end

    around do |example|
      original_store = Rack::Attack.cache.store
      throttle = Rack::Attack.throttles.fetch('req/ip/exponential')
      original_limit = throttle.limit
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      throttle.instance_variable_set(:@limit, 1)
      example.run
    ensure
      throttle.instance_variable_set(:@limit, original_limit)
      Rack::Attack.cache.store = original_store
    end

    def get_as(ip)
      env = Rack::MockRequest.env_for(
        'http://www.bizblasts.com/contact',
        'REMOTE_ADDR' => '127.0.0.1',
        'HTTP_CF_CONNECTING_IP' => ip
      )
      stack.call(env).first
    end

    it 'throttles one visitor without throttling a different visitor' do
      expect(get_as('203.0.113.10')).to eq(200)
      expect(get_as('203.0.113.10')).to eq(429)
      expect(get_as('203.0.113.11')).to eq(200)
    end

    it 'does not let a direct hit borrow a loopback visitor bucket by spoofing CF-Connecting-IP' do
      get_as('203.0.113.10')
      get_as('203.0.113.10')

      env = Rack::MockRequest.env_for(
        'http://www.bizblasts.com/contact',
        'REMOTE_ADDR' => '198.51.100.8',
        'HTTP_CF_CONNECTING_IP' => '203.0.113.10'
      )

      expect(stack.call(env).first).to eq(200)
    end
  end
end
