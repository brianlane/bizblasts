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

  describe 'enforce_service_availability handling' do
    let(:base_attributes) do
      {
        name: 'Availability Enforcement Test',
        description: 'Testing enforcement param handling',
        price: 25.0,
        duration: 30,
        active: true
      }
    end

    context 'POST #create' do
      it 'updates enforcement when nested param provided' do
        post :create, params: { service: base_attributes.merge(enforce_service_availability: '0') }

        created_service = Service.order(created_at: :desc).first
        expect(created_service.enforce_service_availability?).to be false
      end

      it 'does not update enforcement when only top-level param provided' do
        post :create, params: { service: base_attributes, enforce_service_availability: '0' }

        created_service = Service.order(created_at: :desc).first
        expect(created_service.enforce_service_availability?).to be true
      end
    end

    context 'PATCH #update' do
      let!(:service) { create(:service, business: business, enforce_service_availability: true) }

      it 'updates enforcement when nested param provided' do
        patch :update, params: { id: service.id, service: { enforce_service_availability: '0' } }

        service.reload
        expect(service.enforce_service_availability?).to be false
      end

      it 'raises ParameterMissing when only top-level param provided' do
        expect {
          patch :update, params: { id: service.id, enforce_service_availability: '0' }
        }.to raise_error(ActionController::ParameterMissing)

        service.reload
        expect(service.enforce_service_availability?).to be true
      end
    end
  end

end 