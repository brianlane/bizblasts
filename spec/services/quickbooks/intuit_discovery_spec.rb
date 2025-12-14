# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Quickbooks::IntuitDiscovery do
  before do
    Rails.cache.clear
    allow(QuickbooksOauthCredentials).to receive(:environment).and_return('development')
  end

  it 'fetches and caches endpoints from the discovery document' do
    payload = {
      'authorization_endpoint' => 'https://appcenter.intuit.com/connect/oauth2',
      'token_endpoint' => 'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer',
      'revocation_endpoint' => 'https://developer.api.intuit.com/v2/oauth2/tokens/revoke',
      'jwks_uri' => 'https://oauth.platform.intuit.com/op/v1/jwks',
      'issuer' => 'https://oauth.platform.intuit.com/op/v1'
    }

    fake_response = instance_double(Net::HTTPResponse, code: '200', body: payload.to_json)

    expect(Net::HTTP).to receive(:get_response).once.and_return(fake_response)

    first = described_class.endpoints
    second = described_class.endpoints

    expect(first['authorization_endpoint']).to eq(payload['authorization_endpoint'])
    expect(second['token_endpoint']).to eq(payload['token_endpoint'])
  end

  it 'falls back to defaults when discovery fails' do
    allow(Net::HTTP).to receive(:get_response).and_raise(StandardError.new('boom'))

    endpoints = described_class.endpoints

    expect(endpoints).to eq(described_class::DEFAULT_ENDPOINTS)
  end
end
