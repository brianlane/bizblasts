# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Admin Companies", type: :request, admin: true do
  let!(:business) { create(:business, name: "Test Business", subdomain: "testbusiness") }
  
  describe "ActiveAdmin configuration" do
    it "has ActiveAdmin configured correctly" do
      expect(defined?(ActiveAdmin)).to be_truthy
      expect(ActiveAdmin.application).to be_a(ActiveAdmin::Application)
    end
    
    it "has AdminUser model" do
      expect(defined?(AdminUser)).to eq("constant")
      expect(AdminUser).to respond_to(:find_by)
    end
    
    it "has Business model" do
      expect(defined?(Business)).to eq("constant")
      expect(Business.count).to be >= 1
    end
  end
  
  describe "authentication" do
    it "redirects non-authenticated users to login" do
      # Sign out first to test unauthenticated access
      delete destroy_admin_user_session_path
      
      get "/admin/businesses"
      expect(response).to redirect_to(new_admin_user_session_path)
    end
    
    it "allows authenticated admin users to access" do
      get "/admin/businesses"
      expect(response).to be_successful
    end
  end

  describe "GET /admin/businesses" do
    it "lists all businesses" do
      get "/admin/businesses"
      expect(response).to be_successful
      expect(response.body).to include(business.name)
    end
  end
  
  describe "POST /admin/businesses" do
    it "creates a new business" do
      expect {
        post "/admin/businesses", params: { 
          business: { 
            name: "New Business", 
            subdomain: "newbusiness",
            industry: "landscaping"
          } 
        }
      }.to change(Business, :count).by(1)
      
      expect(response).to redirect_to(admin_business_path(Business.last))
      follow_redirect!
      expect(response.body).to include("New Business")
    end
  end
  
  describe "DELETE /admin/businesses/:id" do
    it "deletes a business" do
      # Create a business with minimal associations
      business_to_delete = create(:business, name: "Deletable")
      
      # Track the ID for checking directly
      business_id = business_to_delete.id
      
      # Delete the business
      delete "/admin/businesses/#{business_to_delete.id}"
      
      # Check that the business was deleted
      expect(Business.exists?(business_id)).to be_falsey
      
      # Check redirection
      expect(response).to redirect_to(admin_businesses_path)
    end
  end
end 