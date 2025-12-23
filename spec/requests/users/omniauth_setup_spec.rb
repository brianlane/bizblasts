# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users OAuth Setup', type: :request do
  describe 'POST /users/auth/google_oauth2/setup' do
    it 'stores registration type in session' do
      post user_google_oauth2_setup_path, params: { registration_type: 'client' }

      expect(session[:omniauth_registration_type]).to eq('client')
    end

    it 'stores business registration type in session' do
      post user_google_oauth2_setup_path, params: { registration_type: 'business' }

      expect(session[:omniauth_registration_type]).to eq('business')
    end

    it 'stores return URL in session' do
      post user_google_oauth2_setup_path, params: { return_url: '/my-dashboard' }

      expect(session[:omniauth_return_url]).to eq('/my-dashboard')
    end

    it 'stores origin host in session' do
      post user_google_oauth2_setup_path

      expect(session[:omniauth_origin_host]).to eq('www.example.com')
    end

    it 'stores business ID in session when provided' do
      business = create(:business)
      post user_google_oauth2_setup_path, params: { business_id: business.id }

      expect(session[:omniauth_business_id]).to eq(business.id.to_s)
    end

    it 'redirects to Google OAuth authorization path' do
      post user_google_oauth2_setup_path

      expect(response).to redirect_to(user_google_oauth2_omniauth_authorize_path)
    end
  end
end

