# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Home', type: :request do
  describe 'GET /' do
    it 'returns a successful response' do
      get root_path
      expect(response).to have_http_status(:success)
    end
    
    it 'renders the index template' do
      get root_path
      expect(response).to render_template(:index)
    end
    
    it 'does not require authentication' do
      get root_path
      expect(response).to have_http_status(:success)
    end
  end
  
  describe 'GET /home/debug' do
    context 'when not authenticated' do
      it 'redirects to the login page' do
        get tenant_debug_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
    
    context 'when authenticated' do
      let(:company) { create(:company) }
      let(:user) { create(:user, company: company) }
      
      before do
        sign_in user
        # Manually set current tenant since we're in a request spec
        ActsAsTenant.current_tenant = company
      end
      
      after do
        ActsAsTenant.current_tenant = nil
      end
      
      it 'returns a successful response' do
        get tenant_debug_path
        expect(response).to have_http_status(:success)
      end
      
      it 'renders the debug template' do
        get tenant_debug_path
        expect(response).to render_template(:debug)
      end
    end
  end
end 