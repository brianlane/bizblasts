# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppointmentsController, type: :controller do
  # Include Devise test helpers 
  include Devise::Test::ControllerHelpers
  
  describe "GET #available_slots" do
    let(:company) { create(:company) }
    let(:user) { create(:user, company: company) }
    let(:service) { create(:service, company: company) }
    let(:service_provider) { create(:service_provider, :with_standard_availability, company: company) }
    let(:customer) { create(:customer, company: company) }
    let(:date) { "2023-10-10" }
    
    before do
      # Set the tenant for this test
      ActsAsTenant.current_tenant = company
      
      # Sign in the user
      sign_in user
      
      # Mock the availability service to return predictable slots
      # This avoids testing the actual availability algorithm in this test
      allow(AvailabilityService).to receive(:available_slots).and_return([
        { start_time: Time.current.change(hour: 9), end_time: Time.current.change(hour: 10), formatted_time: '9:00 AM' },
        { start_time: Time.current.change(hour: 14), end_time: Time.current.change(hour: 15), formatted_time: '2:00 PM' }
      ])
    end
    
    it "calls the availability service with correct parameters" do
      # Verify the service is called with the right params
      expect(AvailabilityService).to receive(:available_slots).with(
        service_provider,
        Date.parse(date),
        service,
        interval: 30
      ).and_return([])
      
      get :available_slots, params: { date: date, service_provider_id: service_provider.id, service_id: service.id, interval: 30 }
    end
    
    it "returns a successful response" do
      get :available_slots, params: { date: date, service_provider_id: service_provider.id, service_id: service.id }
      expect(response).to have_http_status(:success)
    end
    
    it "returns the slots as JSON when requested" do
      get :available_slots, params: { date: date, service_provider_id: service_provider.id, service_id: service.id, format: :json }
      expect(response.content_type).to include('application/json')
      
      json_response = JSON.parse(response.body)
      expect(json_response).to be_a(Hash)
      expect(json_response).to have_key('slots')
      expect(json_response['slots'].length).to eq(2)
    end
    
    context "POST #available_slots" do
      it "works the same as GET" do
        expect(AvailabilityService).to receive(:available_slots).with(
          service_provider,
          Date.parse(date),
          service,
          interval: 30
        ).and_return([])
        
        post :available_slots, params: { date: date, service_provider_id: service_provider.id, service_id: service.id, interval: 30 }
        expect(response).to have_http_status(:success)
      end
    end
    
    after do
      # Clean up tenant
      ActsAsTenant.current_tenant = nil
    end
  end
end 