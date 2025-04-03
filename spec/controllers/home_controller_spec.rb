# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HomeController, type: :controller do
  # Include Devise test helpers
  include Devise::Test::ControllerHelpers
  
  describe 'GET #index' do
    it 'returns a successful response' do
      get :index
      expect(response).to have_http_status(:success)
    end
  end
  
  describe 'GET #debug' do
    context 'when not authenticated' do
      it 'redirects to the login page' do
        get :debug
        expect(response).to redirect_to(new_user_session_path)
      end
    end
    
    context 'when authenticated as admin user' do
      let(:admin_user) { create(:admin_user) }
      let!(:company) { create(:company, name: 'Test Company', subdomain: 'test') }
      
      it 'returns a successful response when authentication is mocked' do
        # Similar to our passing request spec, mock both authentication methods
        allow(controller).to receive(:authenticate_admin_user!).and_return(true)
        allow(controller).to receive(:authenticate_user!).and_return(true)
        allow(controller).to receive(:current_admin_user).and_return(admin_user)
        
        # Set tenant explicitly for the controller
        ActsAsTenant.current_tenant = company
        
        get :debug
        expect(response).to have_http_status(:success)
      end
      
      after do
        ActsAsTenant.current_tenant = nil
      end
    end
  end
end 