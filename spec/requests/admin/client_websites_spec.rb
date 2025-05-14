# frozen_string_literal: true
require 'rails_helper'

RSpec.describe "Admin Websites", type: :request, admin: true do
  let(:admin_user) { create(:admin_user) }
  let!(:business1) do
    create(:business, name: "Alpha Biz", hostname: "alpha", host_type: 'subdomain')
  end
  let!(:business2) do
    create(:business, name: "Beta Biz", hostname: "beta", host_type: 'subdomain')
  end

  before do
    sign_in admin_user
  end

  describe "GET /admin/websites" do
    context "when not authenticated" do
      before do
        sign_out admin_user
        get admin_websites_path
      end

      it "redirects non-authenticated users to login" do
        expect(response).to redirect_to(new_admin_user_session_path)
      end
    end

    context "when authenticated as admin" do
      before { get admin_websites_path }

      it "returns http success" do
        expect(response).to have_http_status(:success)
      end

      it "displays the page title" do
        expect(response.body).to include("Websites")
      end

      it "lists all businesses with clickable URLs" do
        [business1, business2].each do |business|
          expect(response.body).to include(business.name)
          expect(response.body).to include(business.hostname)
          # Check for the dynamically generated, clickable URL
          expect(response.body).to include("href=\"#{business.full_url}\"")
        end
      end
    end
  end
end 