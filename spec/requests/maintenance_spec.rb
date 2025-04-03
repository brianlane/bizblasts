# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Maintenance', type: :request do
  describe 'GET /maintenance' do
    it 'returns a service unavailable response' do
      get maintenance_path
      expect(response).to have_http_status(:service_unavailable)
    end
    
    it 'renders the maintenance template' do
      get maintenance_path
      expect(response).to have_http_status(:service_unavailable)
      expect(response.body).to include('Maintenance')
    end
    
    it 'does not require authentication' do
      get maintenance_path
      expect(response).to have_http_status(:service_unavailable)
    end
    
    it 'bypasses tenant setting' do
      # One way to test this is to try to access the maintenance path
      # even when the companies table doesn't exist
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).with('companies').and_return(false)
      
      get maintenance_path
      expect(response).to have_http_status(:service_unavailable)
    end
  end
end 