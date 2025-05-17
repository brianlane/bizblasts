require 'rails_helper'

RSpec.describe "BusinessManager::Settings::Integrations", type: :request do
  let(:business) { create(:business) }
  let(:business_manager_user) { create(:user, :manager, business: business) }
  let!(:integration) { create(:integration, business: business, kind: :webhook, config: { url: 'https://example.com/hook' }) }

  before do
    # IMPORTANT: Set the host to the business's subdomain for SubdomainConstraint to work
    host! "#{business.hostname}.lvh.me"
    # Set the current tenant for ActsAsTenant
    ActsAsTenant.current_tenant = business
    sign_in business_manager_user
  end

  after do
    # Reset the current tenant after each test
    ActsAsTenant.current_tenant = nil
  end

  describe "GET /index" do
    it "renders a successful response" do
      get business_manager_settings_integrations_path
      expect(response).to be_successful
    end

    it "displays integrations" do
      get business_manager_settings_integrations_path
      expect(response.body).to include(integration.kind.humanize.titleize)
      expect(response.body).to include("https://example.com/hook")
    end
  end

  describe "GET /show" do
    it "renders a successful response" do
      get business_manager_settings_integration_path(integration)
      expect(response).to be_successful
    end

    it "displays the integration details" do
      get business_manager_settings_integration_path(integration)
      expect(response.body).to include(integration.kind.humanize.titleize)
      expect(response.body).to include("https://example.com/hook")
    end
  end

  describe "GET /new" do
    it "renders a successful response" do
      get new_business_manager_settings_integration_path
      expect(response).to be_successful
    end
  end

  describe "POST /create" do
    context "with valid parameters" do
      let(:valid_attributes) do
        { kind: :google_calendar, config: { client_id: 'test_client_id' }, business_id: business.id }
      end

      it "creates a new Integration" do
        expect do
          post business_manager_settings_integrations_path, params: { integration: valid_attributes }
        end.to change(Integration, :count).by(1)
      end

      it "redirects to the integrations list" do
        post business_manager_settings_integrations_path, params: { integration: valid_attributes }
        expect(response).to redirect_to(business_manager_settings_integrations_path)
        expect(flash[:notice]).to eq('Integration was successfully created.')
      end
    end

    context "with invalid parameters" do
      let(:invalid_attributes) do
        { kind: nil, config: { url: 'test' } } # kind is required
      end

      it "does not create a new Integration" do
        expect do
          post business_manager_settings_integrations_path, params: { integration: invalid_attributes }
        end.to change(Integration, :count).by(0)
      end

      it "renders an unprocessable_entity response" do # Or :new depending on controller
        post business_manager_settings_integrations_path, params: { integration: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("prohibited this integration from being saved")
      end
    end
  end

  describe "GET /edit" do
    it "renders a successful response" do
      get edit_business_manager_settings_integration_path(integration)
      expect(response).to be_successful
    end
  end

  describe "PATCH /update" do
    context "with valid parameters" do
      let(:new_attributes) do
        { config: { "url" => "https://newexample.com/hook" } }
      end

      it "updates the requested integration" do
        patch business_manager_settings_integration_path(integration), params: { integration: new_attributes }
        integration.reload
        expect(integration.config["url"]).to eq('https://newexample.com/hook')
      end

      it "redirects to the integrations list" do
        patch business_manager_settings_integration_path(integration), params: { integration: new_attributes }
        expect(response).to redirect_to(business_manager_settings_integrations_path)
        expect(flash[:notice]).to eq('Integration was successfully updated.')
      end
    end

    context "with invalid parameters" do
      let(:invalid_attributes) { { kind: nil } }

      it "renders an unprocessable_entity response" do # Or :edit depending on controller
        patch business_manager_settings_integration_path(integration), params: { integration: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("prohibited this integration from being saved")
      end
    end
  end

  describe "DELETE /destroy" do
    it "destroys the requested integration" do
      expect do
        delete business_manager_settings_integration_path(integration)
      end.to change(Integration, :count).by(-1)
    end

    it "redirects to the integrations list" do
      delete business_manager_settings_integration_path(integration)
      expect(response).to redirect_to(business_manager_settings_integrations_path)
      expect(flash[:notice]).to eq('Integration was successfully deleted.')
    end
  end
end 