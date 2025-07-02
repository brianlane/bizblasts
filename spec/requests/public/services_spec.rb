require 'rails_helper'

RSpec.describe 'Services', type: :request do
  include Rails.application.routes.url_helpers

  let(:business) { create(:business) }
  let!(:service_std) do
    create(:service,
           business: business,
           active: true,
           service_type: :standard,
           name: 'Standard Service',
           description: 'Standard desc',
           price: 50.0,
           duration: 30)
  end
  let!(:service_exp) do
    create(:service,
           business: business,
           active: true,
           service_type: :experience,
           name: 'Experience Service',
           description: 'Experience desc',
           min_bookings: 2,
           max_bookings: 5,
           spots: 5,
           price: 75.0,
           duration: 45)
  end

  before do
    host! "#{business.subdomain}.example.com"
    ActsAsTenant.current_tenant = business
  end

  describe 'GET /services' do
    it 'returns a success response' do
      get tenant_services_page_path
      expect(response).to have_http_status(:success)
    end

    it 'displays service names and types' do
      get tenant_services_page_path
      expect(response.body).to include(service_std.name)
      expect(response.body).to include(service_exp.name)
      expect(response.body).to include('Type: Standard')
      expect(response.body).to include('Type: Experience')
    end
  end

  describe 'GET /services/:id' do
    context 'standard service' do
      it 'returns success and shows standard service details' do
        get tenant_service_path(service_std)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(service_std.name)
      end
    end

    context 'experience service' do
      it 'returns success and shows experience service details' do
        get tenant_service_path(service_exp)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(service_exp.name)
        expect(response.body).to include("Minimum Bookings: #{service_exp.min_bookings}")
        expect(response.body).to include("Maximum Bookings: #{service_exp.max_bookings}")
        expect(response.body).to include("Spots Available: #{service_exp.spots}")
      end
    end

    context 'when service not found' do
      it 'redirects to services page with alert' do
        get tenant_service_path(id: 99999)
        expect(response).to redirect_to(tenant_services_page_path)
        expect(flash[:alert]).to eq('Service not found.')
      end
    end
  end
end 