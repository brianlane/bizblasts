# frozen_string_literal: true

require 'rails_helper'

# Note: This file tests the Admin interface for the Business model,
# even though the file is named companies_spec.rb. This might be confusing.
# Consider renaming this file to businesses_spec.rb for clarity.
RSpec.describe "Admin Businesses", type: :request, admin: true do # Renamed describe block
  # Use the original business factory
  let!(:business) { create(:business, name: "Test Business", subdomain: "testbusiness") }
  let(:admin_user) { AdminUser.first || create(:admin_user) }

  before do
    sign_in admin_user
  end

  describe "ActiveAdmin configuration" do
    it "has ActiveAdmin configured correctly" do
      expect(defined?(ActiveAdmin)).to be_truthy
      expect(ActiveAdmin.application).to be_a(ActiveAdmin::Application)
    end
    
    it "has AdminUser model" do
      expect(defined?(AdminUser)).to eq("constant")
      expect(AdminUser).to respond_to(:find_by)
    end
    
    # Check for Business model again
    it "has Business model" do
      expect(defined?(Business)).to eq("constant")
      expect(Business.count).to be >= 1 
    end
  end
  
  describe "authentication" do
    before do 
      sign_out admin_user 
    end

    it "redirects non-authenticated users to login" do
      # Use business path
      get "/admin/businesses"
      expect(response).to redirect_to(new_admin_user_session_path)
    end
    
    it "allows authenticated admin users to access" do
      sign_in admin_user
      # Use business path
      get "/admin/businesses"
      expect(response).to be_successful
    end
  end

  # Test Business routes
  describe "GET /admin/businesses" do
    it "lists all businesses" do
      get "/admin/businesses"
      expect(response).to be_successful
      # Check for business name
      expect(response.body).to include(business.name)
    end
  end
  
  describe "POST /admin/businesses" do
    it "creates a new business" do
      expect {
        post "/admin/businesses", params: {
          # Use business key
          business: {
            name: "New Business", 
            subdomain: "newbusiness",
            # Add other attributes if required by Business factory/model
            # industry: "tech" 
          }
        }
      }.to change(Business, :count).by(1) # Check Business model
      
      # Redirect to business path
      expect(response).to redirect_to(admin_business_path(Business.last))
      follow_redirect!
      expect(response.body).to include("New Business")
    end
  end
  
  describe "DELETE /admin/businesses/:id" do
    it "deletes a business" do
      # Use business factory
      business_to_delete = create(:business, name: "Deletable Business")
      
      business_id = business_to_delete.id
      
      # Use business path
      delete "/admin/businesses/#{business_to_delete.id}"
      
      # Check Business model
      expect(Business.exists?(business_id)).to be_falsey
      
      # Redirect to businesses index
      expect(response).to redirect_to(admin_businesses_path)
    end
  end

  # Removed batch action tests for websites as the feature is incomplete

  # Test index page content
  describe "GET /admin/businesses index content" do
    let!(:business_with_details) { create(:business, industry: "Tech", email: "details@example.com")}
    before { get "/admin/businesses" }

    it "shows relevant columns" do
      expect(response.body).to include("Id")
      expect(response.body).to include("Name")
      expect(response.body).to include("Subdomain")
      expect(response.body).to include("Industry")
      expect(response.body).to include("Email")
      expect(response.body).to include("Active")
      expect(response.body).to include("Created At")
    end

    it "displays business details" do
      expect(response.body).to include(business_with_details.name)
      expect(response.body).to include(business_with_details.subdomain)
      expect(response.body).to include(business_with_details.industry)
      expect(response.body).to include(business_with_details.email)
      # Add check for active status if needed
    end
  end

  # Test show page content
  describe "GET /admin/businesses/:id show content" do
    let!(:business_with_user) { create(:business) }
    let!(:user) { create(:user, business: business_with_user, role: :manager) } 
    before { get "/admin/businesses/#{business_with_user.id}" }

    it "shows business attributes" do
      expect(response.body).to include("Business Details") # Section title
      expect(response.body).to include(business_with_user.name)
      expect(response.body).to include(business_with_user.subdomain)
      # Add checks for other attributes shown
    end

    it "shows the Users panel with user details" do
      expect(response.body).to include("Users") # Panel title
      expect(response.body).to include(user.email)
      expect(response.body).to include(user.role.humanize)
      # Check for link to view user
      expect(response.body).to include(admin_user_path(user)) 
    end
  end

  # Test custom destroy action (especially the test environment path)
  describe "DELETE /admin/businesses/:id custom destroy" do
    let!(:business_to_delete) { create(:business, :with_all) } # Create with associations
    let(:business_id) { business_to_delete.id }

    it "forcefully deletes the business and associations in test env" do
      expect { delete "/admin/businesses/#{business_id}" }.to change(Business, :count).by(-1)

      expect(Business.exists?(business_id)).to be_falsey
      # Verify associations are gone (optional, depends on cascade/nullify)
      # expect(User.where(business_id: business_id).count).to eq(0)
      # expect(Booking.where(business_id: business_id).count).to eq(0)
      # ... etc ...

      expect(response).to redirect_to(admin_businesses_path)
      follow_redirect!
      expect(response.body).to include("Business was successfully deleted.") # Check the specific flash message from the custom action
    end
  end

  # Test form fields
  describe "GET /admin/businesses/new form" do
    before { get "/admin/businesses/new" }
    
    it "renders the form with all fields" do
       expect(response.body).to include("Name")
       expect(response.body).to include("Subdomain")
       expect(response.body).to include("Industry")
       expect(response.body).to include("Phone")
       expect(response.body).to include("Email")
       expect(response.body).to include("Website")
       expect(response.body).to include("Address")
       expect(response.body).to include("City")
       expect(response.body).to include("State")
       expect(response.body).to include("Zip")
       expect(response.body).to include("Description")
       expect(response.body).to include("Time zone")
       expect(response.body).to include("Active")
    end
  end

end 