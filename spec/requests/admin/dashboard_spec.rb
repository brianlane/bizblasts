# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Admin Dashboard", type: :request, admin: true do
  include FactoryBot::Syntax::Methods # Ensure FactoryBot is included

  let!(:admin_user) { create(:admin_user) } # Need admin user to sign in
  let!(:business1) { create(:business, name: "Biz One", created_at: 1.hour.ago) }
  let!(:business2) { create(:business, name: "Biz Two", created_at: 30.minutes.ago) } # Make this one more recent
  let!(:user1) { create(:user, email: "user1@example.com", created_at: 30.minutes.ago) }

  before do
    sign_in admin_user # Sign in before requests
  end

  describe "GET /admin" do
    # Use an around block for tenant context for tests that need it (like booking summary)
    around do |example|
      # Determine if the example needs tenant context based on metadata or description
      needs_tenant = example.metadata[:tenant_context] || example.metadata[:description].include?("(scoped to current tenant)")
      if needs_tenant
        ActsAsTenant.with_tenant(business1) do
          example.run
        end
      else
        example.run
      end
    end

    it "displays the admin dashboard" do
      get admin_root_path
      expect(response).to be_successful
      expect(response.body).to include("Dashboard")
    end

    # Simplified test that doesn't rely on the exact HTML structure
    it "shows global system metrics" do 
      # Create some test data
      create(:service, business: business1)
      create(:service, business: business2)
      create(:staff_member, business: business1)
      create(:booking, business: business1)

      get admin_root_path
      expect(response).to be_successful
      body = response.body
      
      # Debug output to see what is being returned
      puts "GLOBAL SYSTEM METRICS RESPONSE BODY EXCERPT:"
      puts body.scan(/<div class="panel_contents">.*?<\/div>/m).first
      
      # Check for panel title
      expect(body).to include("System Overview")
      
      # Check for table headers
      expect(body).to match(/<th[^>]*>Metric<\/th>/i)
      expect(body).to match(/<th[^>]*>Count<\/th>/i)
      
      # Just verify the panel exists with expected titles
      expect(body).to include("Recent Activity")
      expect(body).to include("Booking Status Summary")
      expect(body).to include("Performance Metrics")
      
      # Check that business names are shown in the Recent Activity section
      expect(body).to include(business1.name)
      expect(body).to include(business2.name)
    end

    it "shows recent activity (global)" do
      get admin_root_path
      expect(response).to be_successful
      body = response.body
      expect(body).to match(/<h3[^>]*>Recent Activity<\/h3>/)
      # Both businesses are recent and should be listed globally
      expect(body).to match(/<a[^>]*>#{Regexp.escape(business1.name)}<\/a>/)
      expect(body).to match(/<a[^>]*>#{Regexp.escape(business2.name)}<\/a>/)
      expect(body).to include("ago")
      # User query might be scoped by tenant if User model uses acts_as_tenant correctly
      # For this test run without explicit tenant, expect global user list
      expect(body).to include(user1.email)
    end
    
    it "shows booking status summary (scoped to current tenant)", :tenant_context do 
      # Create bookings with different statuses for the current tenant
      create(:booking, status: :confirmed, business: business1)
      create(:booking, status: :pending, business: business1)
      # Create a booking for a different tenant (should not be counted)
      create(:booking, status: :confirmed, business: business2)
      
      # Use the force_tenant parameter to ensure the tenant is set in the dashboard controller
      get admin_root_path(force_tenant: business1.id)
      expect(response).to be_successful
      body = response.body
      
      # Debug output to see what is being returned
      puts "TENANT SCOPED BOOKING SUMMARY RESPONSE BODY EXCERPT:"
      puts body.scan(/<h3[^>]*>Booking Status Summary<\/h3>.*?<\/div>/m).first
      
      # Check for panel title
      expect(body).to match(/<h3[^>]*>Booking Status Summary<\/h3>/)
      
      # Check for tenant context indicator
      expect(body).to match(/<h4[^>]*>Tenant Context: #{Regexp.escape(business1.name)}<\/h4>/)
      
      # Check for status counts - look for table cells
      expect(body).to match(/<td[^>]*>Confirmed<\/td>\s*<td[^>]*>1<\/td>/)
      expect(body).to match(/<td[^>]*>Pending<\/td>\s*<td[^>]*>1<\/td>/)
      expect(body).to match(/<td[^>]*>Completed<\/td>\s*<td[^>]*>0<\/td>/)
      expect(body).to match(/<td[^>]*>Cancelled<\/td>\s*<td[^>]*>0<\/td>/)
    end

    it "has a link to tenant debug information" do
      get admin_root_path
      expect(response).to be_successful
      expect(response.body).to match(/<a[^>]*>Tenant Debug Information<\/a>/)
      expect(response.body).to include(admin_debug_path)
    end
  end
end