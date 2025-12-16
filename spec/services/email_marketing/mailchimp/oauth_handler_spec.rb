# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailMarketing::Mailchimp::OauthHandler do
  let(:handler) { described_class.new }
  let(:business) { create(:business) }

  describe '#authorization_url' do
    context 'when credentials are not configured' do
      before do
        allow(MailchimpOauthCredentials).to receive(:configured?).and_return(false)
      end

      it 'returns nil and adds an error' do
        result = handler.authorization_url(business.id, 'https://example.com/callback')

        expect(result).to be_nil
        expect(handler.errors[:missing_credentials]).to be_present
      end
    end

    context 'when credentials are configured' do
      before do
        allow(MailchimpOauthCredentials).to receive(:configured?).and_return(true)
        allow(MailchimpOauthCredentials).to receive(:client_id).and_return('test_client_id')
        allow(MailchimpOauthCredentials).to receive(:authorize_url).and_return('https://login.mailchimp.com/oauth2/authorize')
      end

      it 'returns a valid authorization URL' do
        redirect_uri = 'https://example.com/callback'
        result = handler.authorization_url(business.id, redirect_uri)

        expect(result).to include('https://login.mailchimp.com/oauth2/authorize')
        expect(result).to include('client_id=test_client_id')
        expect(result).to include("redirect_uri=#{CGI.escape(redirect_uri)}")
        expect(result).to include('response_type=code')
        expect(result).to include('state=')
      end
    end
  end

  describe '#handle_callback' do
    let(:redirect_uri) { 'https://example.com/callback' }
    let(:code) { 'test_auth_code' }

    before do
      allow(MailchimpOauthCredentials).to receive(:configured?).and_return(true)
      allow(MailchimpOauthCredentials).to receive(:client_id).and_return('test_client_id')
      allow(MailchimpOauthCredentials).to receive(:client_secret).and_return('test_client_secret')
      allow(MailchimpOauthCredentials).to receive(:token_url).and_return('https://login.mailchimp.com/oauth2/token')
      allow(MailchimpOauthCredentials).to receive(:metadata_url).and_return('https://login.mailchimp.com/oauth2/metadata')
    end

    context 'with valid state and code' do
      let(:state) { Rails.application.message_verifier(:email_marketing_oauth).generate({ business_id: business.id, provider: 'mailchimp', timestamp: Time.current.to_i, nonce: SecureRandom.hex(16) }) }

      it 'creates a connection on successful token exchange', :vcr do
        # Mock the HTTP calls
        token_response = { 'access_token' => 'test_access_token' }
        metadata_response = { 'dc' => 'us1', 'login' => { 'email' => 'test@example.com', 'login_id' => '12345' }, 'accountname' => 'Test Account' }

        allow(handler).to receive(:http_post).and_return([200, token_response])
        allow(handler).to receive(:http_get).and_return([200, metadata_response])

        result = handler.handle_callback(code: code, state: state, redirect_uri: redirect_uri)

        expect(result).to be_a(EmailMarketingConnection)
        expect(result.provider).to eq('mailchimp')
        expect(result.account_email).to eq('test@example.com')
        expect(result.api_server).to eq('us1')
        expect(result.active).to be true
      end
    end

    context 'with invalid state' do
      it 'returns nil and adds an error' do
        result = handler.handle_callback(code: code, state: 'invalid_state', redirect_uri: redirect_uri)

        expect(result).to be_nil
        expect(handler.errors[:invalid_state]).to be_present
      end
    end

    context 'with expired state' do
      let(:expired_state) do
        Rails.application.message_verifier(:email_marketing_oauth).generate({
          business_id: business.id,
          provider: 'mailchimp',
          timestamp: 20.minutes.ago.to_i,
          nonce: SecureRandom.hex(16)
        })
      end

      it 'returns nil and adds an error' do
        result = handler.handle_callback(code: code, state: expired_state, redirect_uri: redirect_uri)

        expect(result).to be_nil
        expect(handler.errors[:expired_state]).to be_present
      end
    end
  end
end
