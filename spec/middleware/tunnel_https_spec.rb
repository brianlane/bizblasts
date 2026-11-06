# frozen_string_literal: true

require 'rails_helper'

# Cloudflare terminates TLS. The tunnel hands the request to Caddy, and Caddy
# proxies to Puma on plain HTTP. If Caddy sets X-Forwarded-Proto to http,
# force_ssl alone would redirect to https and the browser would loop through
# the tunnel. assume_ssl marks the request https before that redirect runs.
RSpec.describe 'tunnel HTTPS assumption' do
  let(:env) do
    Rack::MockRequest.env_for('http://losnemassageaz.com/manage', {
      'HTTP_HOST' => 'losnemassageaz.com',
      'HTTP_X_FORWARDED_PROTO' => 'http',
      'SERVER_PORT' => '3000'
    })
  end

  let(:inner) { ->(app_env) { [200, { 'content-type' => 'text/plain' }, [app_env['rack.url_scheme'].to_s]] } }

  it 'does not redirect an HTTP origin hop when AssumeSSL sits in front of force_ssl' do
    stack = ActionDispatch::AssumeSSL.new(ActionDispatch::SSL.new(inner))

    status, headers, body = stack.call(env)

    expect(status).to eq(200)
    expect(headers['Location'] || headers['location']).to be_nil
    expect(body.join).to eq('https')
    expect(env['HTTP_X_FORWARDED_PROTO']).to eq('https')
  end

  it 'would redirect when force_ssl sees the origin hop as HTTP' do
    stack = ActionDispatch::SSL.new(inner)

    status, headers, = stack.call(env)

    expect(status).to eq(301)
    expect(headers['location']).to start_with('https://losnemassageaz.com')
  end

  it 'keeps production on assume_ssl and force_ssl together' do
    production = Rails.root.join('config/environments/production.rb').read
    expect(production).to match(/config\.assume_ssl\s*=\s*true/)
    expect(production).to match(/config\.force_ssl\s*=\s*true/)
  end
end
