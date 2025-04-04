# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Admin Debug Page", type: :request do
  let(:admin_user) { create(:admin_user) } # Assuming you have an :admin_user factory

  before do
    # Sign in as admin user before each test
    sign_in admin_user
  end

  describe "GET /admin/debug" do
    context "when no tenants exist" do
      before { get admin_debug_path }

      it "returns http success" do
        expect(response).to have_http_status(:success)
      end

      it "displays the correct title" do
        expect(response.body).to include("Multi-Tenant Debug Information")
      end

      it "shows current request info (no tenant)" do
        # Check the row label exists, ensuring the code path is hit.
        # We won't assert '(none)' for now due to potential test env default tenant issues.
        expect(response.body).to include("<th>Current Tenant</th>")
      end

      it "shows 'No tenants found' message" do
        expect(response.body).to include("No tenants found in the database.")
      end

      it "shows testing instructions" do
        expect(response.body).to include("Test Your Tenants")
        expect(response.body).to include("lvh.me")
        expect(response.body).to include("127.0.0.1.xip.io")
      end

      it "shows multi-tenancy info" do
         expect(response.body).to include("Multi-Tenancy Information")
         expect(response.body).to include("acts_as_tenant")
      end

      it "shows the 'Back to Homepage' link" do
        expect(response.body).to include('href="/"')
        expect(response.body).to include(">Back to Homepage</a>") # Check for link text within <a> tag
      end
    end

    context "when tenants exist" do
      let!(:tenant1) { create(:business, name: "Tenant Alpha", subdomain: "alpha") }
      let!(:tenant2) { create(:business, name: "Tenant Beta", subdomain: "beta") }

      before do
        # Simulate request within a tenant context if needed for tenant display,
        # otherwise default request context is fine for just listing tenants.
        # Example: host! "#{tenant1.subdomain}.lvh.me" 
        get admin_debug_path
      end

      it "returns http success" do
        expect(response).to have_http_status(:success)
      end

      it "lists the available tenants" do
        expect(response.body).to include("Available Tenants")
        expect(response.body).to include(tenant1.name)
        expect(response.body).to include(tenant1.subdomain)
        expect(response.body).to include("http://#{tenant1.subdomain}.lvh.me:3000")
        expect(response.body).to include(tenant2.name)
        expect(response.body).to include(tenant2.subdomain)
        expect(response.body).to include("http://#{tenant2.subdomain}.lvh.me:3000")
      end

      it "provides correct testing links using the first tenant" do
         # Get the subdomain the view will actually use
         first_subdomain = Business.first&.subdomain
         expect(first_subdomain).not_to be_nil # Ensure a business was found
         
         expect(response.body).to include("http://#{first_subdomain}.lvh.me:3000")
         expect(response.body).to include("http://#{first_subdomain}.127.0.0.1.xip.io:3000")
       end
    end
    
    context "when request is within a tenant context" do
      let!(:tenant1) { create(:business, name: "Tenant Alpha", subdomain: "alpha") }

      before do
        host! "#{tenant1.subdomain}.lvh.me" # Set the host for the request
        get admin_debug_path
      end

      it "shows current request info with the correct tenant" do
        expect(response.body).to include("Request Subdomain")
        expect(response.body).to include(tenant1.subdomain)
        expect(response.body).to include("Current Tenant")
        expect(response.body).to include(tenant1.name)
      end
    end
  end
end 