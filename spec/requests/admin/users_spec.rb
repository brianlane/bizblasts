# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Admin Users", type: :request, admin: true do
  include FactoryBot::Syntax::Methods
  
  let!(:admin_user) { create(:admin_user) }
  let!(:business1) { create(:business, name: "Business One") }
  let!(:business2) { create(:business, name: "Business Two") }
  
  let!(:manager_user) { create(:user, :manager, business: business1, first_name: "Manager", last_name: "One") }
  let!(:client_user) { create(:user, :client, first_name: "Client", last_name: "Two") }
  let!(:staff_member) { create(:staff_member, business: business1, name: "Staff Guy", position: "Tester") }
  let!(:staff_user) { create(:user, :staff, business: business1, staff_member: staff_member, first_name: "Staff", last_name: "Three") }
  
  before do
    create(:client_business, user: client_user, business: business2)
    sign_in admin_user
  end

  describe "GET /admin/users" do
    it "lists all users" do
      get "/admin/users"
      expect(response).to be_successful
      
      # Check for presence of key data without relying on specific HTML structure
      expect(response.body).to include(manager_user.email)
      expect(response.body).to include(client_user.email)
      expect(response.body).to include(staff_user.email)
      
      # Check for business relationships
      expect(response.body).to include(business1.name)
      
      # Check for staff member info
      expect(response.body).to include("Staff Guy")
      expect(response.body).to include("Tester")
      
      # Check for business count column
      expect(response.body).to include("Businesses Count")
    end
  end

  describe "GET /admin/users/new" do
    it "shows the new user form" do
      get "/admin/users/new"
      expect(response).to be_successful
      expect(response.body).to include("New User")
    end
  end

  describe "POST /admin/users" do
    context "creating a manager user" do
      let(:valid_manager_attributes) do
        { 
          business_id: business1.id,
          email: "new_manager@example.com",
          first_name: "New",
          last_name: "Manager",
          role: "manager",
          active: true,
          password: "password123",
          password_confirmation: "password123"
        }
      end
      
      it "creates a new manager user" do
        expect {
          post "/admin/users", params: { user: valid_manager_attributes }
        }.to change(User.business_users, :count).by(1)
        
        expect(response).to redirect_to(admin_user_path(User.last))
      end
    end

    context "creating a client user" do
      let(:valid_client_attributes) do
        { 
          email: "new_client@example.com",
          first_name: "New",
          last_name: "Client",
          role: "client", 
          active: true,
          password: "password123",
          password_confirmation: "password123"
        }
      end

      it "creates a new client user" do
        expect {
          post "/admin/users", params: { user: valid_client_attributes }
        }.to change(User.clients, :count).by(1)
        
        expect(response).to redirect_to(admin_user_path(User.last))
      end
    end
  end

  describe "PATCH /admin/users/:id" do
    let!(:user_to_update) { create(:user, :manager, business: business1) }

    it "updates the user" do
      patch "/admin/users/#{user_to_update.id}", params: { 
        user: { first_name: "Updated Name" } 
      }
      
      expect(response).to redirect_to(admin_user_path(user_to_update))
      expect(user_to_update.reload.first_name).to eq("Updated Name")
    end
  end

  describe "DELETE /admin/users/:id" do
    let!(:user_to_delete) { create(:user, :client) }

    it "deletes the user" do
      expect {
        delete "/admin/users/#{user_to_delete.id}"
      }.to change(User, :count).by(-1)
      
      expect(response).to redirect_to(admin_users_path)
    end
  end
end