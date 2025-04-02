require 'rails_helper'

RSpec.describe "Admin Dashboard", type: :request do
  let!(:admin_user) { create(:admin_user) }
  let!(:company) { create(:company, name: "Test Company") }
  let!(:user) { create(:user, company: company) }
  let!(:service_template) { create(:service_template, name: "Website Template") }
  let!(:client_website) { create(:client_website, name: "Test Website", company: company, service_template: service_template) }
  let!(:software_product) { create(:software_product, name: "CRM Software") }
  let!(:software_subscription) { create(:software_subscription, company: company, software_product: software_product) }

  before do
    sign_in admin_user
  end

  describe "GET /admin" do
    it "redirects to the dashboard" do
      get "/admin"
      expect(response).to redirect_to("/admin/dashboard")
    end
  end

  describe "GET /admin/dashboard" do
    it "returns a successful response" do
      get "/admin/dashboard"
      expect(response).to be_successful
    end

    it "displays system overview stats" do
      get "/admin/dashboard"
      expect(response.body).to include("System Overview")
      expect(response.body).to include("Total Companies")
      expect(response.body).to include("Total Users")
      expect(response.body).to include("Total Client Websites")
    end

    it "displays recent activity" do
      get "/admin/dashboard"
      expect(response.body).to include("Recent Activity")
      expect(response.body).to include("Test Company")
      expect(response.body).to include("Test Website")
    end
  end

  describe "Authentication" do
    it "redirects to sign in page for unauthenticated users" do
      sign_out admin_user
      get "/admin/dashboard"
      expect(response).to redirect_to("/admin/login")
    end
  end
end 