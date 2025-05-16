require 'rails_helper'
require 'devise/test/integration_helpers'

RSpec.describe "BusinessManager::Settings::Notifications", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:business) { create(:business) }
  let(:business_manager_user) { create(:user, :manager, business: business) }
  let!(:notification_template) { create(:notification_template, business: business) }
  let!(:integration_credential) { create(:integration_credential, business: business) }

  before do
    host! "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
    sign_in business_manager_user
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe "GET /index" do
    it "renders a successful response" do
      get business_manager_settings_notifications_path
      expect(response).to be_successful
    end

    it "displays notification templates and integration credentials" do
      get business_manager_settings_notifications_path
      expect(response.body).to include(notification_template.event_type)
      expect(response.body).to include(integration_credential.provider.humanize)
    end
  end

  describe "GET /new" do
    it "renders a successful response" do
      get new_business_manager_settings_notification_path
      expect(response).to be_successful
    end
  end

  describe "POST /create" do
    context "with valid parameters" do
      let(:valid_attributes) do
        attributes_for(:notification_template, business_id: business.id)
      end

      it "creates a new NotificationTemplate" do
        expect do
          post business_manager_settings_notifications_path, params: { notification_template: valid_attributes }
        end.to change(NotificationTemplate, :count).by(1)
      end

      it "redirects to the index" do
        post business_manager_settings_notifications_path, params: { notification_template: valid_attributes }
        expect(response).to redirect_to(business_manager_settings_notifications_path)
      end
    end

    context "with invalid parameters" do
      let(:invalid_attributes) do
        attributes_for(:notification_template, event_type: "", business_id: business.id)
      end

      it "does not create a new NotificationTemplate" do
        expect do
          post business_manager_settings_notifications_path, params: { notification_template: invalid_attributes }
        end.to change(NotificationTemplate, :count).by(0)
      end

      it "renders a unprocessable_entity response" do
        post business_manager_settings_notifications_path, params: { notification_template: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /edit" do
    it "renders a successful response" do
      get edit_business_manager_settings_notification_path(notification_template)
      expect(response).to be_successful
    end
  end

  describe "PATCH /update" do
    context "with valid parameters" do
      let(:new_attributes) { { subject: "Updated Subject" } }

      it "updates the requested notification_template" do
        patch business_manager_settings_notification_path(notification_template), params: { notification_template: new_attributes }
        notification_template.reload
        expect(notification_template.subject).to eq("Updated Subject")
      end

      it "redirects to the index" do
        patch business_manager_settings_notification_path(notification_template), params: { notification_template: new_attributes }
        expect(response).to redirect_to(business_manager_settings_notifications_path)
      end
    end

    context "with invalid parameters" do
      let(:invalid_attributes) { { subject: "" } }

      it "renders a unprocessable_entity response" do
        patch business_manager_settings_notification_path(notification_template), params: { notification_template: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /destroy" do
    it "destroys the requested notification_template" do
      expect do
        delete business_manager_settings_notification_path(notification_template)
      end.to change(NotificationTemplate, :count).by(-1)
    end

    it "redirects to the notification_templates list" do
      delete business_manager_settings_notification_path(notification_template)
      expect(response).to redirect_to(business_manager_settings_notifications_path)
    end
  end

  describe "GET /edit_credentials" do
    it "renders a successful response" do
      get edit_credentials_business_manager_settings_integration_credentials_path
      expect(response).to be_successful
    end

    it "displays integration credentials" do
      get edit_credentials_business_manager_settings_integration_credentials_path
      expect(response.body).to include(integration_credential.provider.humanize)
      expect(response.body).to include(integration_credential.config.to_json)
    end
  end

  describe "PATCH /update_credentials" do
    let!(:twilio_cred) { create(:integration_credential, business: business, provider: :twilio) }
    let!(:mailgun_cred) { create(:integration_credential, business: business, provider: :mailgun) }

    it "redirects with notice (stub logic)" do
      patch update_credentials_business_manager_settings_integration_credentials_path, params: { integration_credentials: { twilio_cred.id => { config: { api_key: "new_key" } } } }
      expect(response).to redirect_to(business_manager_settings_notifications_path)
      expect(flash[:notice]).to be_present
    end

    # xit "updates the integration credentials (when implemented)" do
    #   # This test should be enabled when update logic is implemented
    #   # patch update_credentials_business_manager_settings_integration_credentials_path, params: { integration_credentials: { twilio_cred.id => { config: { api_key: "new_key" } } } }
    #   # twilio_cred.reload
    #   # expect(twilio_cred.config['api_key']).to eq("new_key")
    # end

    it "handles multiple credentials" do
      patch update_credentials_business_manager_settings_integration_credentials_path, params: { integration_credentials: { twilio_cred.id => { config: { api_key: "twilio_key" } }, mailgun_cred.id => { config: { api_key: "mailgun_key" } } } }
      expect(response).to redirect_to(business_manager_settings_notifications_path)
    end
  end

  describe "POST /create with invalid enum" do
    it "raises error for invalid channel" do
      expect {
        post business_manager_settings_notifications_path, params: { notification_template: attributes_for(:notification_template, channel: 'invalid', business_id: business.id) }
      }.to raise_error(ArgumentError)
    end
  end

  describe "POST /create with missing required fields" do
    it "does not create notification_template if subject is blank" do
      expect {
        post business_manager_settings_notifications_path, params: { notification_template: attributes_for(:notification_template, subject: '', business_id: business.id) }
      }.to change(NotificationTemplate, :count).by(0)
      expect(response).to have_http_status(:unprocessable_entity)
    end
    it "does not create notification_template if body is blank" do
      expect {
        post business_manager_settings_notifications_path, params: { notification_template: attributes_for(:notification_template, body: '', business_id: business.id) }
      }.to change(NotificationTemplate, :count).by(0)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end 