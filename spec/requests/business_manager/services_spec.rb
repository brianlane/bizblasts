require 'rails_helper'

RSpec.describe "/business_manager/services", type: :request do
  # Include route helpers for request specs
  include Rails.application.routes.url_helpers

  # Create necessary data
  let!(:business) { create(:business, hostname: 'testbiz') }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:service) { create(:service, business: business) }

  # Define valid and invalid attributes
  let(:valid_attributes) do
    { name: 'New Service', description: 'Service desc', price: 99.99, duration: 60, active: true, business_id: business.id }
  end
  let(:invalid_attributes) do
    { name: nil, price: -10, duration: 0 }
  end

  # Define host for subdomain routing
  let(:host_params) { { host: "#{business.hostname}.lvh.me" } }

  before do
    # Sign in the manager user before each request test requiring authentication
    sign_in manager
    # Set default host for URL generation within the spec context
    Rails.application.routes.default_url_options[:host] = host_params[:host]
  end

  after do
    # Reset default host
    Rails.application.routes.default_url_options[:host] = nil
  end

  describe "GET /index" do
    it "renders a successful response" do
      service # create service
      # get url_for([:business_manager, :services]), params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] } # Reverted
      get "/services", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      expect(response).to be_successful
      expect(response.body).to include(service.name)
    end
  end

  describe "GET /new" do
    it "renders a successful response" do
      # get url_for([:new, :business_manager, :service]), params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] } # Reverted
      get "/services/new", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      expect(response).to be_successful
    end
  end

  describe "GET /edit" do
    it "renders a successful response" do
      # get url_for([:edit, :business_manager, service]), params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] } # Reverted
      get "/services/#{service.id}/edit", params: {}, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      expect(response).to be_successful
    end
  end

  describe "POST /create" do
    context "with valid parameters" do
      it "creates a new Service" do
        expect {
          # post url_for([:business_manager, :services]), params: { service: valid_attributes }, headers: {}, env: { 'HTTP_HOST' => host_params[:host] } # Reverted
          post "/services", params: { service: valid_attributes }, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        }.to change(Service, :count).by(1)
      end

      it "redirects to the services list" do
        # post url_for([:business_manager, :services]), params: { service: valid_attributes }, headers: {}, env: { 'HTTP_HOST' => host_params[:host] } # Reverted
        post "/services", params: { service: valid_attributes }, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        # expect(response).to redirect_to(url_for([:business_manager, :services])) # Reverted
        expect(response).to redirect_to("/services")
      end
    end

    context "with invalid parameters" do
      it "does not create a new Service" do
        expect {
          # post url_for([:business_manager, :services]), params: { service: invalid_attributes }, headers: {}, env: { 'HTTP_HOST' => host_params[:host] } # Reverted
          post "/services", params: { service: invalid_attributes }, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        }.to change(Service, :count).by(0)
      end

      it "renders a response with 422 status (i.e. to display the 'new' template)" do
        # post url_for([:business_manager, :services]), params: { service: invalid_attributes }, headers: {}, env: { 'HTTP_HOST' => host_params[:host] } # Reverted
        post "/services", params: { service: invalid_attributes }, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PATCH /update" do
    let(:new_attributes) {
      { name: "Updated Service Name", price: 120.00 }
    }

    context "with valid parameters" do
      it "updates the requested service" do
        # patch url_for([:business_manager, service]), params: { service: new_attributes }, headers: {}, env: { 'HTTP_HOST' => host_params[:host] } # Reverted
        patch "/services/#{service.id}", params: { service: new_attributes }, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        service.reload
        expect(service.name).to eq("Updated Service Name")
        expect(service.price).to eq(120.00)
      end

      it "redirects to the services list" do
        # patch url_for([:business_manager, service]), params: { service: new_attributes }, headers: {}, env: { 'HTTP_HOST' => host_params[:host] } # Reverted
        patch "/services/#{service.id}", params: { service: new_attributes }, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        service.reload
        # expect(response).to redirect_to(url_for([:business_manager, :services])) # Reverted
        expect(response).to redirect_to("/services")
      end
    end

    context "with invalid parameters" do
      it "renders a response with 422 status (i.e. to display the 'edit' template)" do
        # patch url_for([:business_manager, service]), params: { service: invalid_attributes }, headers: {}, env: { 'HTTP_HOST' => host_params[:host] } # Reverted
        patch "/services/#{service.id}", params: { service: invalid_attributes }, headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /destroy" do
    it "destroys the requested service" do
      service_to_delete = FactoryBot.create(:service, business: business)
      expect {
        # delete url_for([:business_manager, service_to_delete]), headers: {}, env: { 'HTTP_HOST' => host_params[:host] } # Reverted
        delete "/services/#{service_to_delete.id}", headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      }.to change(Service, :count).by(-1)
    end

    it "redirects to the services list" do
      # delete url_for([:business_manager, service]), headers: {}, env: { 'HTTP_HOST' => host_params[:host] } # Reverted
      delete "/services/#{service.id}", headers: {}, env: { 'HTTP_HOST' => host_params[:host] }
      # expect(response).to redirect_to(url_for([:business_manager, :services])) # Reverted
      expect(response).to redirect_to("/services")
    end
  end
end
