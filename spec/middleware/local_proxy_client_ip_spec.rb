# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Middleware::LocalProxyClientIp do
  let(:inner) do
    lambda do |env|
      request = ActionDispatch::Request.new(env)
      body = [request.ip, request.remote_ip.to_s, env['REMOTE_ADDR']].join('|')
      [200, { 'content-type' => 'text/plain' }, [body]]
    end
  end

  let(:stack) { described_class.new(ActionDispatch::RemoteIp.new(inner)) }

  def call_for(env)
    _status, _headers, body = stack.call(env)
    body.join.split('|')
  end

  def env_for(remote_addr, headers = {})
    Rack::MockRequest.env_for('http://www.bizblasts.com/', headers.merge('REMOTE_ADDR' => remote_addr))
  end

  it 'runs before RemoteIp and Rack::Attack so both see the restored IP' do
    names = Rails.application.middleware.middlewares.map { |entry| entry.klass.name }
    proxy_at = names.index('Middleware::LocalProxyClientIp')
    remote_at = names.index('ActionDispatch::RemoteIp')
    attack_at = names.index('Rack::Attack')

    expect(proxy_at).not_to be_nil
    expect(proxy_at).to be < remote_at
    expect(proxy_at).to be < attack_at
  end

  it 'uses CF-Connecting-IP from a loopback peer and leaves REMOTE_ADDR alone' do
    ip, remote_ip, remote_addr = call_for(env_for('127.0.0.1', 'HTTP_CF_CONNECTING_IP' => '203.0.113.10',
                                                                  'HTTP_X_FORWARDED_FOR' => '127.0.0.1'))

    expect(ip).to eq('203.0.113.10')
    expect(remote_ip).to eq('203.0.113.10')
    expect(remote_addr).to eq('127.0.0.1')
  end

  it 'accepts an IPv6 visitor and an IPv4-mapped loopback peer' do
    ip, remote_ip, = call_for(env_for('::ffff:127.0.0.1', 'HTTP_CF_CONNECTING_IP' => '2001:db8::5'))

    expect(ip).to eq('2001:db8::5')
    expect(remote_ip).to eq('2001:db8::5')
  end

  it 'prefers CF-Connecting-IP over a Forwarded header that still says loopback' do
    ip, = call_for(env_for('::1', 'HTTP_FORWARDED' => 'for=127.0.0.1',
                                'HTTP_CF_CONNECTING_IP' => '203.0.113.44'))

    expect(ip).to eq('203.0.113.44')
  end

  it 'falls back to the rightmost untrusted X-Forwarded-For address' do
    ip, remote_ip, = call_for(env_for('127.0.0.1', 'HTTP_X_FORWARDED_FOR' => '198.51.100.7, 203.0.113.10, 127.0.0.1'))

    expect(ip).to eq('203.0.113.10')
    expect(remote_ip).to eq('203.0.113.10')
  end

  it 'ignores a loopback or garbage CF-Connecting-IP and uses X-Forwarded-For' do
    ip, = call_for(env_for('127.0.0.1', 'HTTP_CF_CONNECTING_IP' => 'not-an-ip',
                                          'HTTP_X_FORWARDED_FOR' => '203.0.113.10'))

    expect(ip).to eq('203.0.113.10')
  end

  it 'keeps the loopback address when no public client IP was forwarded' do
    ip, remote_ip, = call_for(env_for('127.0.0.1'))

    expect(ip).to eq('127.0.0.1')
    expect(remote_ip).to eq('127.0.0.1')
  end

  it 'ignores loopback forwarding headers until TRUST_LOOPBACK_CLIENT_IP is enabled' do
    previous = ENV['TRUST_LOOPBACK_CLIENT_IP']
    ENV['TRUST_LOOPBACK_CLIENT_IP'] = 'false'
    ip, remote_ip, = call_for(env_for('127.0.0.1', 'HTTP_CF_CONNECTING_IP' => '203.0.113.10'))

    expect(ip).to eq('127.0.0.1')
    expect(remote_ip).to eq('127.0.0.1')
  ensure
    ENV['TRUST_LOOPBACK_CLIENT_IP'] = previous
  end

  it 'does not trust forwarding headers from a direct, non-loopback peer' do
    ip, remote_ip, = call_for(env_for('198.51.100.20', 'HTTP_CF_CONNECTING_IP' => '203.0.113.10',
                                                         'HTTP_X_FORWARDED_FOR' => '203.0.113.10'))

    expect(ip).to eq('198.51.100.20')
    expect(remote_ip).to eq('198.51.100.20')
  end

  it 'does not trust forwarding headers from a private address that Rack would treat as a proxy' do
    ip, remote_ip, = call_for(env_for('10.1.2.3', 'HTTP_X_FORWARDED_FOR' => '203.0.113.10',
                                                   'HTTP_CF_CONNECTING_IP' => '203.0.113.10'))

    expect(ip).to eq('10.1.2.3')
    expect(remote_ip).to eq('10.1.2.3')
  end
end
