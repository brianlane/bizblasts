# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TenantScoped, type: :concern do
  # Create test models and data for testing the concern
  let(:business1) { create(:business) }
  let(:business2) { create(:business) }
  let!(:service1) { create(:service, business: business1, name: "Service A") }
  let!(:service2) { create(:service, business: business2, name: "Service B") }

  describe "scoping behavior" do
    before do
      # Clear tenant to prevent test pollution
      ActsAsTenant.current_tenant = nil
    end

    it "scopes queries to the current tenant" do
      ActsAsTenant.with_tenant(business1) do
        expect(Service.all).to include(service1)
        expect(Service.all).not_to include(service2)
      end
      
      ActsAsTenant.with_tenant(business2) do
        expect(Service.all).to include(service2)
        expect(Service.all).not_to include(service1)
      end
    end

    it "associates new records with the current tenant" do
      ActsAsTenant.with_tenant(business1) do
        new_service = Service.create!(name: "New Service", duration: 60, price: 100)
        expect(new_service.business).to eq(business1)
      end
    end

    it "prevents creating records without a tenant" do
      ActsAsTenant.current_tenant = nil
      
      # Attempt to create a service without a tenant should fail
      new_service = Service.new(name: "Tenant-less Service", duration: 60, price: 100)
      expect(new_service).not_to be_valid
      expect(new_service.errors[:business]).to include("must exist")
    end
  end

  describe "default_scope" do
    it "is automatically applied to all queries" do
      # Clear any previous tenant
      ActsAsTenant.current_tenant = nil
      
      # Set tenant and check that the scope is applied
      ActsAsTenant.current_tenant = business1
      expect(Service.count).to eq(1)
      expect(Service.first).to eq(service1)
      
      # Change tenant and check that the scope changes
      ActsAsTenant.current_tenant = business2
      expect(Service.count).to eq(1)
      expect(Service.first).to eq(service2)
    end
  end
end 