# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Business Manager Dashboard", type: :system do
  let!(:business) { create(:business) }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:staff) { create(:user, :staff, business: business) }
  let!(:client) { create(:user, :client) }
  let!(:other_business) { create(:business) }
  let!(:other_manager) { create(:user, :manager, business: other_business) }
  let!(:service) { create(:service, business: business) }
  let!(:customer) { create(:tenant_customer, business: business) }
  let!(:recent_booking) { create(:booking, business: business, service: service, tenant_customer: customer, start_time: 3.days.ago) }
  let!(:upcoming_booking) { create(:booking, business: business, service: service, tenant_customer: customer, start_time: 3.days.from_now) }

  before do
    # Revert back to rack_test for stability
    driven_by(:rack_test)
    # Don't set app_host or tenant here - we'll do it in each context
  end

  context "when not signed in" do
    before do
      switch_to_subdomain(business.subdomain)
    end
    
    it "redirects to the login page" do
      visit business_manager_dashboard_path
      expect(page).to have_current_path(new_user_session_path, ignore_query: true)
      expect(page).to have_content("Welcome Back")
      expect(page).to have_content("Sign in to your account")
    end
  end

  context "when signed in as a manager of the current business" do
    before do
      switch_to_subdomain(business.subdomain)
      login_as(manager, scope: :user)
      visit business_manager_dashboard_path
    end

    it "allows access to the dashboard" do
      expect(page).to have_current_path(business_manager_dashboard_path)
      expect(page).to have_content("Welcome to #{business.name}")
      expect(page).to have_content("Upcoming Appointments (Next 7 Days)")

      # Check for Recent Bookings widget
      within('#recent-bookings-widget') do
        expect(page).to have_content(service.name)
        expect(page).to have_content(customer.full_name)
        displayed_time = Booking.find(recent_booking.id).local_start_time.strftime("%a, %b %d, %Y at %I:%M %p")
        expect(page).to have_content(displayed_time)
      end

      # Check for Upcoming Appointments widget
      expect(page).to have_selector('#upcoming-appointments-widget') do |widget|
        expect(widget).to have_selector('h3', text: 'Upcoming Appointments (Next 7 Days)')
      end

      # Check for Analytics widget
      within('#website-stats-widget') do
        expect(page).to have_content("Website Analytics")
        expect(page).to have_content("Last 30 days")
        expect(page).to have_content("Visitors")
        expect(page).to have_content("Page Views")
        expect(page).to have_content("Avg Duration")
        expect(page).to have_content("Bounce Rate")
        expect(page).to have_content("Conversions")
        expect(page).to have_content("Conversion Rate")
        expect(page).to have_link("View Full Analytics", href: business_manager_analytics_path)
      end

      # Check for Quick Actions including Services link
      within('#quick-actions-widget') do
        expect(page).to have_link("Create Booking") # Placeholder check
        expect(page).to have_link("Edit Website", href: edit_business_manager_settings_website_pages_path)
      end
    end
  end

  context "when signed in as staff of the current business" do
    before do
      switch_to_subdomain(business.subdomain)
      login_as(staff, scope: :user)
      visit business_manager_dashboard_path
    end

    it "allows access to the dashboard" do
      expect(page).to have_current_path(business_manager_dashboard_path)
      expect(page).to have_content("Welcome to #{business.name}")
    end
  end

  context "when signed in as a client of the current business" do
    it "redirects to the client dashboard" do
      # First sign in as the client on the business subdomain
      switch_to_subdomain(business.subdomain)
      login_as(client, scope: :user)
      
      # Visit the business manager dashboard - should get redirected
      visit business_manager_dashboard_path
      
      # Should see "You are not authorized" message while still on business subdomain
      expect(page).to have_content("You are not authorized to access this area")
      
      # Now follow the redirect to the main domain client dashboard
      switch_to_main_domain
      visit dashboard_path
      
      # Should now see the client dashboard
      expect(page).to have_content("Welcome, #{client.full_name}!")
    end
  end

  context "when signed in as a manager of a different business" do
    before do
      # First sign in as the other business manager
      switch_to_main_domain
      login_as(other_manager, scope: :user)
      
      # Now switch to the first business subdomain and try to access its dashboard
      switch_to_subdomain(business.subdomain)
      visit business_manager_dashboard_path
    end

    it "redirects away and shows an authorization error" do
      expect(page).to have_content("You are not authorized to access this area")
    end
  end
end 