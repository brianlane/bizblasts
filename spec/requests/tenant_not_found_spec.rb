require 'rails_helper'

RSpec.describe 'Tenant Not Found', type: :request do
  describe 'when accessing a non-existent subdomain' do
    before do
      # Set the host to a non-existent subdomain
      host! 'nonexistent.lvh.me'
    end

    it 'returns 404 status' do
      get '/'
      expect(response).to have_http_status(:not_found)
    end

    it 'renders the tenant_not_found template' do
      get '/'
      expect(response.body).to include('Business Not Found')
      expect(response.body).to include('nonexistent')
      expect(response.body).to include('Visit BizBlasts')
    end

    it 'includes proper styling and layout' do
      get '/'
      expect(response.body).to include('linear-gradient(135deg, #667eea 0%, #764ba2 100%)')
      expect(response.body).to include('🏢')
      expect(response.body).to include('404 ERROR')
    end

    it 'includes helpful action buttons' do
      get '/'
      expect(response.body).to include('href="https://bizblasts.com"')
      expect(response.body).to include('Browse Businesses')
    end

    it 'includes support information' do
      get '/'
      expect(response.body).to include('Looking for your business?')
      expect(response.body).to include('contact support')
    end
  end
end 