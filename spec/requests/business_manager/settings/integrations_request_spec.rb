require 'rails_helper'

RSpec.describe "BusinessManager::Settings::Integrations", type: :request do
  let(:business) { create(:business) }
  let(:business_manager_user) { create(:user, :manager, business: business) }

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

    it "includes Google Business integration UI" do
      get business_manager_settings_integrations_path
      expect(response.body).to include("Google Business Reviews")
      expect(response.body).to include("More Integrations Coming Soon")
    end
  end
end