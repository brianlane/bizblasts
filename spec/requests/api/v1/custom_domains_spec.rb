# frozen_string_literal: true

require 'rails_helper'

# Verifies the on_demand_tls callback used by Caddy.
#
# Caddy is the only legitimate caller of this endpoint. It always hits us on
# loopback with `Host: localhost` (because its `ask` URL is
# http://localhost:3000/...). Any other shape — external host header even
# via loopback, public IP peer, etc. — must be rejected, otherwise an
# attacker can enumerate which custom domains are provisioned by hitting
# https://bizblasts.com/api/v1/custom_domains/verify (Bugbot MEDIUM:
# "Verify endpoint trusts all proxies").
RSpec.describe 'Api::V1::CustomDomains verify endpoint', type: :request do
  let(:caddy_headers) do
    {
      'HOST'        => 'localhost',
      'REMOTE_ADDR' => '127.0.0.1'
    }
  end

  before do
    allow(AllowedHostService).to receive(:allowed?).and_return(false)
    allow(AllowedHostService).to receive(:main_domain?).and_return(false)
    allow(AllowedHostService).to receive(:valid_platform_subdomain?).and_return(false)
  end

  describe 'GET /api/v1/custom_domains/verify' do
    context 'when called by Caddy (loopback peer + localhost host)' do
      it 'returns 200 for an allowed platform host' do
        allow(AllowedHostService).to receive(:allowed?).with('bizblasts.com').and_return(true)
        allow(AllowedHostService).to receive(:main_domain?).with('bizblasts.com').and_return(true)

        get '/api/v1/custom_domains/verify',
            params: { domain: 'bizblasts.com' },
            env: caddy_headers

        expect(response).to have_http_status(:ok)
      end

      it 'returns 200 for a registered custom domain (provider lookup succeeds)' do
        allow(AllowedHostService).to receive(:allowed?).with('shop.example.com').and_return(true)
        provider = instance_double('Provider')
        allow(DomainProvider).to receive(:current).and_return(provider)
        allow(provider).to receive(:find_domain_by_name).with('shop.example.com').and_return('id' => 'caddy:shop.example.com', 'name' => 'shop.example.com')

        get '/api/v1/custom_domains/verify',
            params: { domain: 'shop.example.com' },
            env: caddy_headers

        expect(response).to have_http_status(:ok)
      end

      it 'returns 404 for a pre-setup custom domain (AllowedHostService says yes but provider has no entry)' do
        allow(AllowedHostService).to receive(:allowed?).with('shop.example.com').and_return(true)
        provider = instance_double('Provider')
        allow(DomainProvider).to receive(:current).and_return(provider)
        allow(provider).to receive(:find_domain_by_name).with('shop.example.com').and_return(nil)

        get '/api/v1/custom_domains/verify',
            params: { domain: 'shop.example.com' },
            env: caddy_headers

        expect(response).to have_http_status(:not_found)
      end

      it 'returns 404 for a disallowed domain' do
        get '/api/v1/custom_domains/verify',
            params: { domain: 'attacker.example' },
            env: caddy_headers

        expect(response).to have_http_status(:not_found)
      end

      it 'accepts 127.0.0.1 as a Host as well' do
        allow(AllowedHostService).to receive(:allowed?).with('bizblasts.com').and_return(true)
        allow(AllowedHostService).to receive(:main_domain?).with('bizblasts.com').and_return(true)

        get '/api/v1/custom_domains/verify',
            params: { domain: 'bizblasts.com' },
            env: caddy_headers.merge('HOST' => '127.0.0.1')

        expect(response).to have_http_status(:ok)
      end

      it 'returns 400 when domain is missing' do
        get '/api/v1/custom_domains/verify', env: caddy_headers

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when reached over the public site via Caddy reverse_proxy' do
      # Externally-originated requests come in with loopback REMOTE_ADDR
      # (Caddy reverse_proxies to Puma over 127.0.0.1) but with the public
      # hostname in the Host header. This must be rejected — otherwise the
      # endpoint is anonymously reachable from the Internet.
      it 'returns 403 when Host is the public site' do
        allow(AllowedHostService).to receive(:allowed?).with('victim.com').and_return(true)

        get '/api/v1/custom_domains/verify',
            params: { domain: 'victim.com' },
            env: { 'HOST' => 'bizblasts.com', 'REMOTE_ADDR' => '127.0.0.1' }

        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 when Host is a customer subdomain' do
        get '/api/v1/custom_domains/verify',
            params: { domain: 'victim.com' },
            env: { 'HOST' => 'default.bizblasts.com', 'REMOTE_ADDR' => '127.0.0.1' }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when called from a non-loopback peer' do
      it 'returns 403 even if Host is localhost' do
        get '/api/v1/custom_domains/verify',
            params: { domain: 'whatever.com' },
            env: { 'HOST' => 'localhost', 'REMOTE_ADDR' => '203.0.113.10' }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
