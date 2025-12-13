# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoMeeting::OauthHandler do
  let(:business) { create(:business) }
  let(:staff_member) { create(:staff_member, business: business) }

  subject(:handler) { described_class.new }

  describe '#initialize' do
    it 'initializes empty errors' do
      expect(handler.errors).to be_empty
    end
  end

  describe '#authorization_url' do
    context 'for Zoom' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ZOOM_CLIENT_ID').and_return('test_client_id')
        allow(ENV).to receive(:[]).with('ZOOM_CLIENT_SECRET').and_return('test_client_secret')
      end

      it 'returns a valid Zoom authorization URL' do
        url = handler.authorization_url('zoom', business.id, staff_member.id, 'https://example.com/callback')

        expect(url).to start_with('https://zoom.us/oauth/authorize')
        expect(url).to include('client_id=test_client_id')
        expect(url).to include('response_type=code')
        expect(url).to include('state=')
      end

      context 'when credentials are missing' do
        before do
          allow(ENV).to receive(:[]).with('ZOOM_CLIENT_ID').and_return(nil)
        end

        it 'returns nil' do
          url = handler.authorization_url('zoom', business.id, staff_member.id, 'https://example.com/callback')
          expect(url).to be_nil
        end

        it 'adds error' do
          handler.authorization_url('zoom', business.id, staff_member.id, 'https://example.com/callback')
          expect(handler.errors[:missing_credentials]).to be_present
        end
      end
    end

    context 'for Google Meet' do
      before do
        allow(GoogleOauthCredentials).to receive(:configured?).and_return(true)
        allow(GoogleOauthCredentials).to receive(:client_id).and_return('test_google_client_id')
      end

      it 'returns a valid Google authorization URL' do
        url = handler.authorization_url('google_meet', business.id, staff_member.id, 'https://example.com/callback')

        expect(url).to start_with('https://accounts.google.com/o/oauth2/auth')
        expect(url).to include('client_id=test_google_client_id')
        expect(url).to include('scope=')
        expect(url).to include('access_type=offline')
      end

      context 'when credentials are missing' do
        before do
          allow(GoogleOauthCredentials).to receive(:configured?).and_return(false)
        end

        it 'returns nil' do
          url = handler.authorization_url('google_meet', business.id, staff_member.id, 'https://example.com/callback')
          expect(url).to be_nil
        end
      end
    end

    context 'for unsupported provider' do
      it 'returns nil' do
        url = handler.authorization_url('unsupported', business.id, staff_member.id, 'https://example.com/callback')
        expect(url).to be_nil
      end

      it 'adds error' do
        handler.authorization_url('unsupported', business.id, staff_member.id, 'https://example.com/callback')
        expect(handler.errors[:unsupported_provider]).to be_present
      end
    end
  end

  describe '#refresh_token' do
    let(:connection) do
      create(:video_meeting_connection,
             business: business,
             staff_member: staff_member,
             provider: :zoom,
             access_token: 'old_token',
             refresh_token: 'refresh_token',
             token_expires_at: 1.hour.ago)
    end

    context 'for Zoom' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ZOOM_CLIENT_ID').and_return('test_client_id')
        allow(ENV).to receive(:[]).with('ZOOM_CLIENT_SECRET').and_return('test_client_secret')
      end

      it 'refreshes the token successfully' do
        # Mock successful HTTP response
        http_double = instance_double(Net::HTTP)
        response_double = instance_double(Net::HTTPResponse,
          code: '200',
          body: {
            access_token: 'new_access_token',
            refresh_token: 'new_refresh_token',
            expires_in: 3600
          }.to_json
        )

        allow(Net::HTTP).to receive(:new).and_return(http_double)
        allow(http_double).to receive(:use_ssl=)
        allow(http_double).to receive(:request).and_return(response_double)

        expect(handler.refresh_token(connection)).to be true

        connection.reload
        expect(connection.access_token).to eq('new_access_token')
        expect(connection.refresh_token).to eq('new_refresh_token')
      end

      it 'handles API errors' do
        # Mock error HTTP response
        http_double = instance_double(Net::HTTP)
        response_double = instance_double(Net::HTTPResponse,
          code: '401',
          body: { error: 'invalid_grant', reason: 'Token expired' }.to_json
        )

        allow(Net::HTTP).to receive(:new).and_return(http_double)
        allow(http_double).to receive(:use_ssl=)
        allow(http_double).to receive(:request).and_return(response_double)

        expect(handler.refresh_token(connection)).to be false
        expect(handler.errors[:refresh_failed]).to be_present

        connection.reload
        expect(connection.active).to be false
      end

      context 'when credentials are missing' do
        before do
          allow(ENV).to receive(:[]).with('ZOOM_CLIENT_ID').and_return(nil)
          allow(ENV).to receive(:[]).with('ZOOM_CLIENT_SECRET').and_return(nil)
          allow(ENV).to receive(:[]).with('ZOOM_CLIENT_ID_DEV').and_return(nil)
          allow(ENV).to receive(:[]).with('ZOOM_CLIENT_SECRET_DEV').and_return(nil)
        end

        it 'returns false and deactivates connection' do
          expect(handler.refresh_token(connection)).to be false
          expect(handler.errors[:missing_credentials]).to be_present

          connection.reload
          expect(connection.active).to be false
        end
      end
    end

    context 'for Google Meet' do
      let(:google_connection) do
        create(:video_meeting_connection,
               business: business,
               staff_member: staff_member,
               provider: :google_meet,
               access_token: 'old_token',
               refresh_token: 'refresh_token',
               token_expires_at: 1.hour.ago)
      end

      before do
        allow(GoogleOauthCredentials).to receive(:configured?).and_return(true)
        allow(GoogleOauthCredentials).to receive(:credentials).and_return({
          client_id: 'test_client_id',
          client_secret: 'test_client_secret'
        })
      end

      it 'refreshes the token using Signet' do
        auth_client = instance_double(Signet::OAuth2::Client)
        allow(Signet::OAuth2::Client).to receive(:new).and_return(auth_client)
        allow(auth_client).to receive(:refresh!)
        allow(auth_client).to receive(:access_token).and_return('new_access_token')
        allow(auth_client).to receive(:refresh_token).and_return('new_refresh_token')
        allow(auth_client).to receive(:expires_at).and_return(1.hour.from_now)

        expect(handler.refresh_token(google_connection)).to be true

        google_connection.reload
        expect(google_connection.access_token).to eq('new_access_token')
      end

      it 'handles Signet authorization errors' do
        auth_client = instance_double(Signet::OAuth2::Client)
        allow(Signet::OAuth2::Client).to receive(:new).and_return(auth_client)
        allow(auth_client).to receive(:refresh!).and_raise(Signet::AuthorizationError.new('Invalid grant'))

        expect(handler.refresh_token(google_connection)).to be false
        expect(handler.errors[:refresh_failed]).to be_present

        google_connection.reload
        expect(google_connection.active).to be false
      end
    end

    context 'for unsupported provider' do
      let(:unsupported_connection) do
        connection = create(:video_meeting_connection,
                           business: business,
                           staff_member: staff_member,
                           provider: :zoom,
                           access_token: 'token',
                           refresh_token: 'refresh')
        # Stub the provider method to return an unsupported value
        allow(connection).to receive(:provider).and_return('unsupported')
        allow(connection).to receive(:zoom?).and_return(false)
        allow(connection).to receive(:google_meet?).and_return(false)
        connection
      end

      it 'returns false' do
        expect(handler.refresh_token(unsupported_connection)).to be false
      end
    end
  end

  describe 'state parameter security' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ZOOM_CLIENT_ID').and_return('test_client_id')
      allow(ENV).to receive(:[]).with('ZOOM_CLIENT_SECRET').and_return('test_client_secret')
    end

    it 'generates cryptographically signed state' do
      url = handler.authorization_url('zoom', business.id, staff_member.id, 'https://example.com/callback')
      uri = URI.parse(url)
      params = CGI.parse(uri.query)
      state = params['state'].first

      # State should be verifiable
      expect {
        Rails.application.message_verifier(:video_meeting_oauth).verify(state)
      }.not_to raise_error
    end

    it 'includes timestamp in state for expiration checking' do
      url = handler.authorization_url('zoom', business.id, staff_member.id, 'https://example.com/callback')
      uri = URI.parse(url)
      params = CGI.parse(uri.query)
      state = params['state'].first

      state_data = Rails.application.message_verifier(:video_meeting_oauth).verify(state)
      expect(state_data['timestamp']).to be_present
      expect(state_data['timestamp']).to be_within(60).of(Time.current.to_i)
    end

    it 'includes nonce in state for replay protection' do
      url = handler.authorization_url('zoom', business.id, staff_member.id, 'https://example.com/callback')
      uri = URI.parse(url)
      params = CGI.parse(uri.query)
      state = params['state'].first

      state_data = Rails.application.message_verifier(:video_meeting_oauth).verify(state)
      expect(state_data['nonce']).to be_present
      expect(state_data['nonce'].length).to eq(32) # 16 bytes = 32 hex chars
    end
  end
end
