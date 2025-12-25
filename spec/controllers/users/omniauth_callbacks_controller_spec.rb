# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::OmniauthCallbacksController, type: :controller do
  before do
    @request.env['devise.mapping'] = Devise.mappings[:user]
  end

  describe 'GET #google_oauth2' do
    context 'with valid OAuth response' do
      before do
        mock_google_oauth2(email: 'oauth@example.com', first_name: 'Test', last_name: 'User', uid: '123456')
        request.env['omniauth.auth'] = OmniAuth.config.mock_auth[:google_oauth2]
      end

      context 'when user exists with matching email' do
        let!(:existing_user) { create(:user, email: 'oauth@example.com', provider: nil, uid: nil) }

        it 'links OAuth account and signs in existing user' do
          expect {
            get :google_oauth2
          }.not_to change(User, :count)

          existing_user.reload
          expect(existing_user.provider).to eq('google_oauth2')
          expect(existing_user.uid).to eq('123456')
          expect(controller.current_user).to eq(existing_user)
        end
      end

      context 'when user exists with matching provider/uid' do
        let!(:existing_user) { create(:user, email: 'different@example.com', provider: 'google_oauth2', uid: '123456') }

        it 'signs in the existing user' do
          expect {
            get :google_oauth2
          }.not_to change(User, :count)

          expect(controller.current_user).to eq(existing_user)
        end
      end

      context 'with business registration type in session' do
        before do
          session[:omniauth_registration_type] = 'business'
        end

        it 'redirects to business registration to complete setup' do
          get :google_oauth2

          expect(response).to redirect_to(new_business_registration_path)
          expect(session[:omniauth_data]).to be_present
        end
      end

      context 'with return_url in session' do
        before do
          session[:omniauth_return_url] = '/dashboard'
        end

        it 'redirects to the stored return URL for existing users' do
          create(:user, email: 'oauth@example.com')
          get :google_oauth2

          expect(response).to redirect_to('/dashboard')
        end
      end
    end
  end
end
