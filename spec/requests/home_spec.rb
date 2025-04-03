# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Home', type: :request do
  describe 'GET /' do
    it 'returns a successful response' do
      get root_path
      expect(response).to have_http_status(:success)
    end
    
    it 'renders the correct content for index' do
      get root_path
      # Check for content instead of template name
      expect(response.body).to include("Welcome") # Adjust if needed
    end
    
    it 'does not require authentication' do
      get root_path
      expect(response).to have_http_status(:success)
    end
  end
  
  describe 'GET /home/debug (now moved to /admin/debug)' do
    it 'redirects to the admin debug page' do
      get '/home/debug'
      expect(response).to redirect_to('/admin/debug')
    end
  end

  describe 'GET /admin/debug' do
    context 'when not authenticated as admin' do
      it 'redirects to the admin login page' do
        get '/admin/debug'
        expect(response).to redirect_to('/admin/login')
      end
    end
  end
end 