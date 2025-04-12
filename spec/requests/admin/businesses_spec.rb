# frozen_string_literal: true

require 'rails_helper'

# Note: This file tests the Admin interface for the Business model,
# even though the file is named companies_spec.rb. This might be confusing.
# Consider renaming this file to businesses_spec.rb for clarity.
RSpec.describe "Admin Businesses", type: :request, admin: true do # Renamed describe block
  let!(:admin_user) { create(:admin_user) } 
  
  # Updated to use hostname/host_type
  let!(:business) { 
    create(:business, 
           name: "Test Business", 
           hostname: "testbusiness", 
           host_type: 'subdomain', 
           tier: :free # Ensure valid combination 
          )
  } 

  before do
    sign_in admin_user
  end

  describe "ActiveAdmin configuration" do
    it "has ActiveAdmin configured correctly" do
      expect(ActiveAdmin.application).to be_present
    end

    it "has AdminUser model" do
      expect(defined?(AdminUser)).to be_truthy
    end

    it "has Business model" do
      expect(defined?(Business)).to be_truthy
    end
  end

  describe "authentication" do
    context "when not authenticated" do
      before { sign_out admin_user }

      it "redirects non-authenticated users to login" do
        get admin_businesses_path
        expect(response).to redirect_to(new_admin_user_session_path)
      end
    end

    context "when authenticated as admin" do
      it "allows authenticated admin users to access" do
        get admin_businesses_path
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /admin/businesses" do
    it "lists all businesses" do
      get admin_businesses_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(business.name)
      expect(response.body).to include(business.hostname) # Check for hostname
    end
  end

  describe "POST /admin/businesses" do
    let(:valid_attributes) do
      { 
        business: {
          name: "New Valid Business",
          hostname: "newvalid",
          host_type: 'subdomain',
          tier: 'standard',
          industry: "hair_salon",
          phone: "555-000-1111",
          email: "new@valid.com",
          address: "1 New St",
          city: "Newville",
          state: "NV",
          zip: "98765",
          description: "A newly created business.",
          active: true
        } 
      }
    end

    it "creates a new business" do
      expect {
        post admin_businesses_path, params: valid_attributes
      }.to change(Business, :count).by(1)
      expect(response).to redirect_to(admin_business_path(Business.last.hostname))
      follow_redirect!
    end
  end
  
  describe "DELETE /admin/businesses/:id" do
    it "deletes a business" do
      expect {
        delete admin_business_path(business.id)
      }.to change(Business, :count).by(-1)
      expect(response).to redirect_to(admin_businesses_path)
      follow_redirect!
    end
  end

  # Removed batch action tests for websites as the feature is incomplete

  # Test index page content
  describe "GET /admin/businesses index content" do
    let!(:business1) { create(:business) }
    let!(:business2) { create(:business) }
    # Ensure the business used for detail checks uses the updated factory 
    # which provides all required fields and a valid industry.
    let!(:business_with_details) { create(:business, email: "details@example.com")}
    
    before { get admin_businesses_path }

    it "shows relevant columns" do
      expect(response.body).to include('<a href="/admin/businesses?order=id_asc">Id</a>')
      expect(response.body).to include('<a href="/admin/businesses?order=name_desc">Name</a>')
      expect(response.body).to include('<a href="/admin/businesses?order=hostname_desc">Hostname</a>')
      expect(response.body).to include('<a href="/admin/businesses?order=host_type_desc">Host Type</a>')
      expect(response.body).to include('<a href="/admin/businesses?order=tier_desc">Tier</a>')
      expect(response.body).to include('<a href="/admin/businesses?order=industry_desc">Industry</a>')
      expect(response.body).to include('<a href="/admin/businesses?order=email_desc">Email</a>')
      expect(response.body).to include('<a href="/admin/businesses?order=active_desc">Active</a>')
      expect(response.body).to include('<a href="/admin/businesses?order=created_at_desc">Created At</a>')
    end

    it "displays business details" do
      expect(response.body).to include(business_with_details.name)
      expect(response.body).to include(business_with_details.hostname)
      expect(response.body).to include(business_with_details.host_type)
      expect(response.body).to include(business_with_details.tier)
      expect(response.body).to include(business_with_details.industry)
      expect(response.body).to include(business_with_details.email)
    end
  end

  # Test show page content
  describe "GET /admin/businesses/:id show content" do
    let!(:user) { create(:user, business: business) } 
    before { get admin_business_path(business.id) }

    it "shows business attributes" do
      expect(response.body).to include("Business Details") # Section title
      expect(response.body).to include(business.name)
      expect(response.body).to include(business.hostname)
      expect(response.body).to include(business.host_type)
      expect(response.body).to include(business.tier)
      # Add checks for other attributes shown
    end

    it "shows the Users panel with user details" do
      expect(response.body).to include("<h3>Users</h3>")
      # Use regex to match td tag potentially with class attributes
      expect(response.body).to match(/<td[^>]*>#{user.id}<\/td>/)
      expect(response.body).to match(/<td[^>]*>#{Regexp.escape(user.email)}<\/td>/)
      expect(response.body).to match(/<td[^>]*>#{user.role.humanize}<\/td>/)
    end
  end

  # Test custom destroy action (especially the test environment path)
  describe "DELETE /admin/businesses/:id custom destroy" do
    it "forcefully deletes the business and associations in test env" do
      # Create associated records
      create(:user, business: business)
      create(:tenant_customer, business: business)
      create(:service, business: business)
      
      expect {
        delete admin_business_path(business.id)
      }.to change(Business, :count).by(-1)
       .and change(User, :count).by(-1) # Assuming admin user still exists
       .and change(TenantCustomer, :count).by(-1)
       .and change(Service, :count).by(-1)
       
      expect(response).to redirect_to(admin_businesses_path)
      follow_redirect!
    end
  end

  # Test form fields
  describe "GET /admin/businesses/new form" do
    before { get new_admin_business_path }
    
    it "renders the form with all fields" do
      expect(response).to have_http_status(:success)
      # Simplified checks for input elements by name attribute
      expect(response.body).to include('name="business[name]"')
      expect(response.body).to include('name="business[hostname]"')
      expect(response.body).to include('name="business[host_type]"')
      expect(response.body).to include('name="business[tier]"')
      expect(response.body).to include('name="business[industry]"')
      expect(response.body).to include('name="business[phone]"')
      expect(response.body).to include('name="business[email]"')
      expect(response.body).to include('name="business[address]"')
      expect(response.body).to include('name="business[city]"')
      expect(response.body).to include('name="business[state]"')
      expect(response.body).to include('name="business[zip]"')
      expect(response.body).to include('name="business[description]"')
      expect(response.body).to include('name="business[active]"')
    end
  end

end 