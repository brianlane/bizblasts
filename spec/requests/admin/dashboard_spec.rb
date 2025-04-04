# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Admin Dashboard", type: :request, admin: true do
  describe "GET /admin" do
    it "displays the admin dashboard" do
      get admin_root_path
      expect(response).to be_successful
      expect(response.body).to include("Dashboard")
    end

    it "shows system metrics" do
      get admin_root_path
      expect(response).to be_successful
      expect(response.body).to include("System Overview")
    end
    
    it "has a link to tenant debug information" do
      get admin_root_path
      expect(response).to be_successful
      expect(response.body).to include("Tenant Debug Information")
    end
  end
end 