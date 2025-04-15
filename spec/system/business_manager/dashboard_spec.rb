# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Business Manager Dashboard", type: :system do
  let!(:business) { create(:business, hostname: 'testbiz') }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:staff) { create(:user, :staff, business: business, email: 'staff@test.com') }
  let!(:client) { create(:user, :client, email: 'client@test.com') }
  let!(:other_business) { create(:business, hostname: 'otherbiz') }
  let!(:other_manager) { create(:user, :manager, business: other_business, email: 'othermanager@test.com') }

  before do
    # Revert back to rack_test for stability
    driven_by(:rack_test) 
    Capybara.app_host = "http://#{business.hostname}.example.com"
    # Remove server_host/port for rack_test
  end

  context "when not signed in" do
    it "redirects to the login page" do
      visit business_manager_dashboard_path
      expect(page).to have_current_path(new_user_session_path)
      expect(page).to have_content("Log in") # Or whatever your login page title is
    end
  end

  context "when signed in as a manager of the current business" do
    before do
      login_as(manager, scope: :user)
      visit business_manager_dashboard_path
    end

    it "allows access to the dashboard" do
      expect(page).to have_current_path(business_manager_dashboard_path)
      expect(page).to have_content("Welcome to #{business.name} Dashboard")
      expect(page).to have_content("Upcoming Bookings") # Check for dashboard content
    end
  end

  context "when signed in as staff of the current business" do
    before do
      login_as(staff, scope: :user)
      visit business_manager_dashboard_path
    end

    it "allows access to the dashboard" do
      expect(page).to have_current_path(business_manager_dashboard_path)
      expect(page).to have_content("Welcome to #{business.name} Dashboard")
    end
  end

  context "when signed in as a client of the current business" do
    before do
      # Sign in the client user on the main domain
      login_as(client, scope: :user)
      Capybara.app_host = "http://#{business.hostname}.example.com"
      # Visit the business dashboard - this should redirect to client dashboard
      visit business_manager_dashboard_path
    end

    after do
      # Reset app_host after the test
      Capybara.app_host = nil
    end

    it "redirects to the client dashboard" do
      # Client should see the client dashboard after the redirect
      expect(page).to have_content("Client Dashboard")
      # Verify we're on the client dashboard
      expect(page).to have_current_path(dashboard_path)
    end
  end

  context "when signed in as a manager of a different business" do
    before do
      # Must login via the main domain first if devise routes aren't tenant specific
      # Or adjust Capybara.app_host temporarily if login needs to happen on other tenant
      # For simplicity, assume login happens and then visit the target tenant dashboard
      Capybara.app_host = "http://www.example.com" # Go to main domain to log in
      login_as(other_manager, scope: :user)
      Capybara.app_host = "http://#{business.hostname}.example.com" # Switch back to target tenant
      visit business_manager_dashboard_path
    end

    it "redirects away and shows an authorization error" do
       expect(page).not_to have_current_path(business_manager_dashboard_path)
       expect(page).to have_current_path(root_path) # Assumes redirect to root
       expect(page).to have_content("You are not authorized to access this area.")
    end
  end

  # Reset Capybara app_host after tests
  after do
    Capybara.app_host = nil
  end
end 