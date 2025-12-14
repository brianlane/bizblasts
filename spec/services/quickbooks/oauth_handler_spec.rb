# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Quickbooks::OauthHandler do
  let(:business) { create(:business) }

  before do
    allow(QuickbooksOauthCredentials).to receive(:configured?).and_return(true)
    allow(QuickbooksOauthCredentials).to receive(:client_id).and_return('client-id')
    allow(QuickbooksOauthCredentials).to receive(:client_secret).and_return('client-secret')
    allow(QuickbooksOauthCredentials).to receive(:environment).and_return('development')
  end

  it 'generates an authorization url with signed state' do
    url = described_class.new.authorization_url(business.id, 'https://example.com/callback')

    expect(url).to include('https://appcenter.intuit.com/connect/oauth2?')
    expect(url).to include('client_id=client-id')
    expect(url).to include('redirect_uri=https%3A%2F%2Fexample.com%2Fcallback')
    expect(url).to include('scope=com.intuit.quickbooks.accounting')
    expect(url).to include('state=')
  end

  it 'creates a QuickbooksConnection on successful callback' do
    handler = described_class.new

    # Build a valid signed state
    state = Rails.application.message_verifier(:quickbooks_oauth).generate({
      business_id: business.id,
      timestamp: Time.current.to_i,
      nonce: SecureRandom.hex(8)
    })

    # Stub token exchange
    token_body = {
      'access_token' => 'access-token',
      'refresh_token' => 'refresh-token',
      'expires_in' => 3600,
      'x_refresh_token_expires_in' => 86400,
      'scope' => 'com.intuit.quickbooks.accounting'
    }

    fake_response = instance_double(Net::HTTPResponse, code: '200', body: token_body.to_json)

    fake_http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(fake_http)
    allow(fake_http).to receive(:use_ssl=)
    allow(fake_http).to receive(:request).and_return(fake_response)

    connection = handler.handle_callback(
      code: 'auth-code',
      state: state,
      realm_id: '12345',
      redirect_uri: 'https://example.com/callback'
    )

    expect(connection).to be_present
    expect(connection).to be_a(QuickbooksConnection)
    expect(connection.business_id).to eq(business.id)
    expect(connection.realm_id).to eq('12345')
    expect(connection.active).to eq(true)
  end
end
