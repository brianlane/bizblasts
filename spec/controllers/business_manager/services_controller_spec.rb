require 'rails_helper'

RSpec.describe BusinessManager::ServicesController, type: :controller do
  let(:business) { create(:business) }
  let(:manager_user) { create(:user, :manager, business: business) }

  before do
    request.host = "#{business.subdomain}.example.com"
    ActsAsTenant.current_tenant = business
    sign_in manager_user
  end

  describe 'POST #create' do
    let(:valid_attributes) do
      {
        name: 'Test Service',
        description: 'A test service',
        price: 49.99,
        duration: 60,
        active: true,
        tips_enabled: true
      }
    end

    it 'creates a new service with tips enabled' do
      expect {
        post :create, params: { service: valid_attributes }
      }.to change(Service, :count).by(1)

      service = Service.last
      expect(service.tips_enabled).to be true
    end

    it 'creates a new service with tips disabled' do
      valid_attributes[:tips_enabled] = false

      post :create, params: { service: valid_attributes }
      
      service = Service.last
      expect(service.tips_enabled).to be false
    end
  end

  describe 'PATCH #update' do
    let!(:service) { create(:service, business: business, tips_enabled: false) }

    it 'updates the service tips_enabled status' do
      patch :update, params: { 
        id: service.id, 
        service: { tips_enabled: true } 
      }

      service.reload
      expect(service.tips_enabled).to be true
    end

    it 'updates the service to disable tips' do
      service.update!(tips_enabled: true)

      patch :update, params: { 
        id: service.id, 
        service: { tips_enabled: false } 
      }

      service.reload
      expect(service.tips_enabled).to be false
    end
  end
end 