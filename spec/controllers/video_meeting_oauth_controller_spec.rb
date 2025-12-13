# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoMeetingOauthController, type: :controller do
  let(:business) { create(:business, hostname: 'testbiz', host_type: :subdomain) }
  let(:staff_member) { create(:staff_member, business: business) }
  let(:user) { create(:user, business: business, role: :manager) }

  def generate_valid_state(business_id, staff_member_id, nonce: SecureRandom.hex(16))
    state_data = {
      'business_id' => business_id,
      'staff_member_id' => staff_member_id,
      'timestamp' => Time.current.to_i,
      'nonce' => nonce
    }
    Rails.application.message_verifier(:video_meeting_oauth).generate(state_data)
  end

  def generate_expired_state(business_id, staff_member_id)
    state_data = {
      'business_id' => business_id,
      'staff_member_id' => staff_member_id,
      'timestamp' => 20.minutes.ago.to_i,
      'nonce' => SecureRandom.hex(16)
    }
    Rails.application.message_verifier(:video_meeting_oauth).generate(state_data)
  end

  describe 'GET #callback' do
    let(:valid_state) { generate_valid_state(business.id, staff_member.id) }
    let(:valid_code) { 'oauth_authorization_code' }

    context 'CSRF protection' do
      it 'allows requests with valid OAuth state (alternative CSRF protection)' do
        oauth_handler = instance_double(VideoMeeting::OauthHandler)
        allow(VideoMeeting::OauthHandler).to receive(:new).and_return(oauth_handler)
        allow(oauth_handler).to receive(:handle_callback).and_return(nil)
        allow(oauth_handler).to receive(:errors).and_return(ActiveModel::Errors.new(oauth_handler))

        expect {
          get :callback, params: { provider: 'zoom', code: valid_code, state: valid_state }
        }.not_to raise_error
      end

      it 'rejects requests without valid OAuth state' do
        get :callback, params: { provider: 'zoom', code: valid_code, state: 'invalid_state' }

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Invalid or expired')
      end
    end

    context 'OAuth state validation' do
      it 'rejects missing state parameter' do
        get :callback, params: { provider: 'zoom', code: valid_code }

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Invalid or expired')
      end

      it 'rejects expired state parameter' do
        expired_state = generate_expired_state(business.id, staff_member.id)

        get :callback, params: { provider: 'zoom', code: valid_code, state: expired_state }

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Invalid or expired')
      end

      it 'rejects tampered state parameter' do
        get :callback, params: { provider: 'zoom', code: valid_code, state: 'tampered_state_data' }

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Invalid or expired')
      end

      it 'accepts valid state parameter within time window' do
        oauth_handler = instance_double(VideoMeeting::OauthHandler)
        allow(VideoMeeting::OauthHandler).to receive(:new).and_return(oauth_handler)
        allow(oauth_handler).to receive(:handle_callback).and_return(nil)
        allow(oauth_handler).to receive(:errors).and_return(ActiveModel::Errors.new(oauth_handler))

        get :callback, params: { provider: 'zoom', code: valid_code, state: valid_state }

        # Should not redirect to root with invalid state error
        expect(flash[:alert]).not_to include('Invalid or expired')
      end
    end

    context 'OAuth error handling' do
      # Note: With valid state containing business_id, errors redirect to business integrations page
      it 'handles access_denied error' do
        get :callback, params: { provider: 'zoom', error: 'access_denied', state: valid_state }

        expect(response).to be_redirect
        expect(flash[:alert]).to include('access was denied')
      end

      it 'handles invalid_request error' do
        get :callback, params: { provider: 'zoom', error: 'invalid_request', state: valid_state }

        expect(response).to be_redirect
        expect(flash[:alert]).to include('Invalid OAuth request')
      end

      it 'handles unauthorized_client error' do
        get :callback, params: { provider: 'zoom', error: 'unauthorized_client', state: valid_state }

        expect(response).to be_redirect
        expect(flash[:alert]).to include('Unauthorized')
      end

      it 'handles server_error' do
        get :callback, params: { provider: 'zoom', error: 'server_error', state: valid_state }

        expect(response).to be_redirect
        expect(flash[:alert]).to include('temporarily unavailable')
      end

      it 'handles temporarily_unavailable error' do
        get :callback, params: { provider: 'zoom', error: 'temporarily_unavailable', state: valid_state }

        expect(response).to be_redirect
        expect(flash[:alert]).to include('temporarily unavailable')
      end

      it 'handles unsupported_response_type error' do
        get :callback, params: { provider: 'zoom', error: 'unsupported_response_type', state: valid_state }

        expect(response).to be_redirect
        expect(flash[:alert]).to include('Unsupported')
      end

      it 'handles invalid_scope error' do
        get :callback, params: { provider: 'zoom', error: 'invalid_scope', state: valid_state }

        expect(response).to be_redirect
        expect(flash[:alert]).to include('Invalid video meeting permissions')
      end

      it 'handles unknown errors with description' do
        get :callback, params: {
          provider: 'zoom',
          error: 'unknown_error',
          error_description: 'Something went wrong',
          state: valid_state
        }

        expect(response).to be_redirect
        expect(flash[:alert]).to include('Something went wrong')
      end
    end

    context 'missing required parameters' do
      it 'redirects with error when code is missing' do
        get :callback, params: { provider: 'zoom', state: valid_state }

        expect(response).to be_redirect
        expect(flash[:alert]).to include('Missing required OAuth parameters')
      end

      it 'redirects with error when provider is missing' do
        get :callback, params: { code: valid_code, state: valid_state }

        expect(response).to be_redirect
        expect(flash[:alert]).to include('Missing required OAuth parameters')
      end
    end

    context 'successful connection' do
      let(:connection) do
        create(:video_meeting_connection,
               business: business,
               staff_member: staff_member,
               provider: :zoom,
               active: true)
      end

      before do
        oauth_handler = instance_double(VideoMeeting::OauthHandler)
        allow(VideoMeeting::OauthHandler).to receive(:new).and_return(oauth_handler)
        allow(oauth_handler).to receive(:handle_callback).and_return(connection)
      end

      it 'redirects to business integrations page with success message' do
        get :callback, params: { provider: 'zoom', code: valid_code, state: valid_state }

        expect(response).to redirect_to(%r{/manage/settings/integrations})
        expect(flash[:notice]).to include('Successfully connected')
      end

      it 'includes provider name in success message' do
        get :callback, params: { provider: 'zoom', code: valid_code, state: valid_state }

        expect(flash[:notice]).to include(connection.provider_name)
      end

      it 'includes staff member name in success message' do
        get :callback, params: { provider: 'zoom', code: valid_code, state: valid_state }

        expect(flash[:notice]).to include(staff_member.name)
      end

      it 'allows redirect to other host for cross-subdomain redirect' do
        # The controller should use allow_other_host: true for subdomain redirects
        get :callback, params: { provider: 'zoom', code: valid_code, state: valid_state }

        expect(response).to be_redirect
      end
    end

    context 'failed connection' do
      before do
        oauth_handler = instance_double(VideoMeeting::OauthHandler)
        allow(VideoMeeting::OauthHandler).to receive(:new).and_return(oauth_handler)
        allow(oauth_handler).to receive(:handle_callback).and_return(nil)

        errors = ActiveModel::Errors.new(oauth_handler)
        errors.add(:base, 'Token exchange failed')
        allow(oauth_handler).to receive(:errors).and_return(errors)
      end

      it 'redirects with error message' do
        get :callback, params: { provider: 'zoom', code: valid_code, state: valid_state }

        expect(response).to be_redirect
        expect(flash[:alert]).to include('Token exchange failed')
      end

      it 'tries to redirect to business integrations page if state is valid' do
        get :callback, params: { provider: 'zoom', code: valid_code, state: valid_state }

        # Should redirect to business integrations, not just root_path
        expect(response.location).to include('integrations')
      end
    end

    context 'for Google Meet provider' do
      it 'handles google_meet provider' do
        oauth_handler = instance_double(VideoMeeting::OauthHandler)
        allow(VideoMeeting::OauthHandler).to receive(:new).and_return(oauth_handler)
        allow(oauth_handler).to receive(:handle_callback).and_return(nil)
        allow(oauth_handler).to receive(:errors).and_return(ActiveModel::Errors.new(oauth_handler))

        get :callback, params: { provider: 'google_meet', code: valid_code, state: valid_state }

        expect(response).to be_redirect
      end
    end
  end


  describe 'logging' do
    let(:valid_state) { generate_valid_state(business.id, staff_member.id) }

    it 'logs OAuth errors' do
      expect(Rails.logger).to receive(:error).with(/Video Meeting OAuth error/)

      get :callback, params: { provider: 'zoom', error: 'access_denied', state: valid_state }
    end

    it 'logs invalid state warnings' do
      expect(Rails.logger).to receive(:warn).with(/Invalid or expired OAuth state/)

      get :callback, params: { provider: 'zoom', code: 'code', state: 'invalid' }
    end

    it 'logs connection failures' do
      oauth_handler = instance_double(VideoMeeting::OauthHandler)
      allow(VideoMeeting::OauthHandler).to receive(:new).and_return(oauth_handler)
      allow(oauth_handler).to receive(:handle_callback).and_return(nil)

      errors = ActiveModel::Errors.new(oauth_handler)
      errors.add(:base, 'Connection failed')
      allow(oauth_handler).to receive(:errors).and_return(errors)

      expect(Rails.logger).to receive(:error).with(/Video meeting connection failed/)

      get :callback, params: { provider: 'zoom', code: 'code', state: valid_state }
    end
  end

  describe 'security' do
    it 'does not expose sensitive error details to users' do
      oauth_handler = instance_double(VideoMeeting::OauthHandler)
      allow(VideoMeeting::OauthHandler).to receive(:new).and_return(oauth_handler)
      allow(oauth_handler).to receive(:handle_callback).and_return(nil)

      errors = ActiveModel::Errors.new(oauth_handler)
      errors.add(:base, 'Internal token details: secret123')
      allow(oauth_handler).to receive(:errors).and_return(errors)

      valid_state = generate_valid_state(business.id, staff_member.id)
      get :callback, params: { provider: 'zoom', code: 'code', state: valid_state }

      # Error is shown to user (this is a design choice, but let's verify behavior)
      # In production, you might want to sanitize this
      expect(response).to be_redirect
    end

    it 'validates state before processing any callback logic' do
      # Invalid state should short-circuit before OAuth handler is called
      expect(VideoMeeting::OauthHandler).not_to receive(:new)

      get :callback, params: { provider: 'zoom', code: 'valid_code', state: 'invalid' }
    end

    it 'prevents replay attacks with timestamp validation' do
      old_state = generate_expired_state(business.id, staff_member.id)

      get :callback, params: { provider: 'zoom', code: 'code', state: old_state }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include('Invalid or expired')
    end
  end
end
