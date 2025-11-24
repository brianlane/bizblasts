# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleBusinessOauthController, type: :controller do
  let(:business) { create(:business) }
  let(:user) { create(:user, :manager, business: business) }
  let(:oauth_state) { SecureRandom.hex(32) }
  let(:authorization_code) { 'test_auth_code_123' }

  describe 'GET #callback - Security Tests (CWE-598)' do
    context 'when OAuth callback succeeds' do
      let(:google_accounts) do
        [
          { name: 'Test Business Account', account_id: '123456' }
        ]
      end
      let(:google_tokens) do
        { access_token: 'token123', refresh_token: 'refresh123' }
      end

      before do
        # Set up session with OAuth state
        session[:oauth_business_id] = business.id
        session[:oauth_user_id] = user.id
        session[:oauth_state] = oauth_state

        # Mock successful OAuth exchange
        allow(GoogleBusinessProfileService).to receive(:exchange_code_and_fetch_profiles)
          .and_return({
            success: true,
            accounts: google_accounts,
            tokens: google_tokens
          })
      end

      it 'stores success notice in session, not URL parameters' do
        get :callback, params: { code: authorization_code, state: oauth_state }

        # Verify notice is stored in session
        expect(session[:oauth_flash_notice]).to eq('Connected to Google! Please select your business account below.')
        expect(session[:oauth_flash_alert]).to be_nil

        # Verify redirect URL does NOT contain flash messages as parameters
        expect(response).to redirect_to(%r{/manage/settings/integrations})
        redirect_url = response.location
        expect(redirect_url).not_to include('oauth_notice')
        expect(redirect_url).not_to include('oauth_alert')
        expect(redirect_url).not_to include('Connected+to+Google')
      end

      it 'includes show_google_accounts parameter in URL (non-sensitive data)' do
        get :callback, params: { code: authorization_code, state: oauth_state }

        redirect_url = response.location
        expect(redirect_url).to include('show_google_accounts=true')
      end

      it 'stores Google accounts and tokens in session for selection' do
        get :callback, params: { code: authorization_code, state: oauth_state }

        expect(session[:google_business_accounts]).to eq(google_accounts)
        expect(session[:google_oauth_tokens]).to eq(google_tokens)
      end
    end

    context 'when OAuth callback fails' do
      before do
        # Set up session with OAuth state
        session[:oauth_business_id] = business.id
        session[:oauth_user_id] = user.id
        session[:oauth_state] = oauth_state

        # Mock failed OAuth exchange
        allow(GoogleBusinessProfileService).to receive(:exchange_code_and_fetch_profiles)
          .and_return({
            success: false,
            error: 'Failed to connect to Google Business Profile.'
          })
      end

      it 'stores error alert in session, not URL parameters' do
        get :callback, params: { code: authorization_code, state: oauth_state }

        # Verify alert is stored in session
        expect(session[:oauth_flash_alert]).to eq('Failed to connect to Google Business Profile.')
        expect(session[:oauth_flash_notice]).to be_nil

        # Verify redirect URL does NOT contain flash messages as parameters
        expect(response).to redirect_to(%r{/manage/settings/integrations})
        redirect_url = response.location
        expect(redirect_url).not_to include('oauth_alert')
        expect(redirect_url).not_to include('oauth_notice')
        expect(redirect_url).not_to include('Failed+to+connect')
      end
    end

    context 'when OAuth state is invalid (security check)' do
      before do
        session[:oauth_business_id] = business.id
        session[:oauth_user_id] = user.id
        session[:oauth_state] = oauth_state
      end

      it 'stores CSRF error in session, not URL' do
        get :callback, params: { code: authorization_code, state: 'invalid_state' }

        # Should redirect to error handler, which uses Rails flash (not session for main domain)
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('OAuth state mismatch. Please try again.')
      end
    end

    context 'when session expires (no business_id)' do
      it 'redirects to error page with secure flash' do
        get :callback, params: { code: authorization_code, state: oauth_state }

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('OAuth session expired. Please try again.')
      end
    end
  end

  describe 'Security: Session-based flash storage' do
    it 'does not expose sensitive OAuth messages in URLs' do
      # Set up minimal session
      session[:oauth_business_id] = business.id
      session[:oauth_user_id] = user.id
      session[:oauth_state] = oauth_state

      # Mock successful OAuth
      allow(GoogleBusinessProfileService).to receive(:exchange_code_and_fetch_profiles)
        .and_return({
          success: true,
          accounts: [{ name: 'Test' }],
          tokens: { access_token: 'token' }
        })

      get :callback, params: { code: authorization_code, state: oauth_state }

      redirect_url = URI.parse(response.location)
      query_params = CGI.parse(redirect_url.query || '')

      # Verify NO sensitive data in query parameters
      expect(query_params).not_to have_key('oauth_notice')
      expect(query_params).not_to have_key('oauth_alert')
      expect(query_params).not_to have_key('notice')
      expect(query_params).not_to have_key('alert')

      # Verify data is in session instead
      expect(session[:oauth_flash_notice]).to be_present
    end
  end
end
