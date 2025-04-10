# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Admin Users", type: :request, admin: true do
  include FactoryBot::Syntax::Methods
  
  let!(:admin_user) { create(:admin_user) }
  let!(:business1) { create(:business, name: "Business One") }
  let!(:business2) { create(:business, name: "Business Two") }
  
  # Users no longer have :admin role, use :manager instead for business-level admin
  # Clients don't strictly need a business_id upon creation anymore
  let!(:manager_user) { create(:user, :manager, business: business1, first_name: "Manager", last_name: "One") }
  let!(:client_user) { create(:user, :client, first_name: "Client", last_name: "Two") } # No business needed here
  let!(:staff_member) { create(:staff_member, business: business1, name: "Staff Guy", position: "Tester") }
  let!(:staff_user) { create(:user, :staff, business: business1, staff_member: staff_member, first_name: "Staff", last_name: "Three") }
  
  # Associate client_user with business2 via ClientBusiness for testing display
  before do
    create(:client_business, user: client_user, business: business2)
  end

  before do
    sign_in admin_user
    # No tenant setting needed
  end

  describe "GET /admin/users" do
    it "lists all users" do
      get "/admin/users"
      expect(response).to be_successful
      
      # Check manager user (requires business)
      expect(response.body).to include(manager_user.email)
      expect(response.body).to include(manager_user.full_name)
      expect(response.body).to include("Manager") # Role
      expect(response.body).to include(business1.name)
      
      # Check client user (no direct business link in table, check associated count)
      expect(response.body).to include(client_user.email)
      expect(response.body).to include(client_user.full_name)
      expect(response.body).to include("Client") # Role
      expect(response.body).to include("Associated Businesses")
      expect(response.body).to match(/<tr.*id=\"user_#{client_user.id}\".*>.*<td.*>#{Regexp.quote(client_user.email)}<\/td>.*<td.*associated_businesses.*>1<\/td>.*<\/tr>/m)
      
      # Check staff user (requires business)
      expect(response.body).to include(staff_user.email)
      expect(response.body).to include("Staff Guy") # Staff member name
      expect(response.body).to include("Tester") # Staff member position
      expect(response.body).to include(admin_staff_member_path(staff_member)) # Link to staff member
    end
  end

  describe "GET /admin/users/new" do
    it "shows the new user form" do
      get "/admin/users/new"
      expect(response).to be_successful
      expect(response.body).to include("New User")
      expect(response.body).to include("User Details")
      # Check that business/staff fields are present but possibly hidden by JS
      expect(response.body).to include("user_business_id")
      expect(response.body).to include("user_staff_member_id")
    end
  end

  describe "POST /admin/users" do
    context "creating a manager user (requires business)" do
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
        
        new_user = User.find_by(email: "new_manager@example.com")
        expect(new_user).not_to be_nil
        expect(new_user.business).to eq(business1)
        expect(new_user.role).to eq("manager")
        expect(response).to redirect_to(admin_user_path(new_user))
      end
      
      it "fails without a business_id" do
         expect {
          post "/admin/users", params: { user: valid_manager_attributes.except(:business_id) }
        }.not_to change(User, :count)
        expect(response.body).to include("can&#39;t be blank")
      end
    end

    context "creating a client user (does not require business)" do
      let(:valid_client_attributes) do
        { 
          # No business_id needed
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
        
        new_user = User.find_by(email: "new_client@example.com")
        expect(new_user).not_to be_nil
        expect(new_user.business_id).to be_nil
        expect(new_user.role).to eq("client")
        expect(response).to redirect_to(admin_user_path(new_user))
      end
    end
  end

  # Skipping GET show test for now

  describe "PATCH /admin/users/:id" do
    let!(:manager_to_update) { create(:user, :manager, business: business1, first_name: "Original", last_name: "Manager") }
    let!(:staff_member2) { create(:staff_member, business: business1, name: "Other Staff") }
    
    context "updating a manager user" do
      let(:updated_manager_attributes) do
        { 
          first_name: "Updated Mgr First",
          last_name: "Updated Mgr Last",
          active: false,
          staff_member_id: staff_member2.id # Assign staff member
          # Cannot change business_id or role easily here due to validation dependencies
        }
      end
      
      it "updates the manager user" do
        patch "/admin/users/#{manager_to_update.id}", params: { user: updated_manager_attributes }
        manager_to_update.reload
        expect(response).to redirect_to(admin_user_path(manager_to_update))
        expect(manager_to_update.first_name).to eq("Updated Mgr First")
        expect(manager_to_update.active).to be false
        expect(manager_to_update.staff_member).to eq(staff_member2)
        expect(manager_to_update.business).to eq(business1) # Ensure business didn't change
      end
    end
    
    context "updating a client user" do
      let!(:client_to_update) { create(:user, :client, first_name: "Original", last_name: "Client") }
      let(:updated_client_attributes) do
        { 
          first_name: "Updated Client First",
          last_name: "Updated Client Last",
          active: false,
          business_id: nil # Explicitly ensure business_id is not sent or is nil
          # Cannot assign staff_member_id to a client directly via this form
        }
      end
      
      it "updates the client user" do
        patch "/admin/users/#{client_to_update.id}", params: { user: updated_client_attributes }
        client_to_update.reload
        expect(response).to redirect_to(admin_user_path(client_to_update))
        expect(client_to_update.first_name).to eq("Updated Client First")
        expect(client_to_update.active).to be false
        expect(client_to_update.business_id).to be_nil
      end
    end
  end

  describe "DELETE /admin/users/:id" do
    it "deletes the user" do
      user_to_delete = create(:user, :client, email: "delete@me.com")
      expect {
        delete "/admin/users/#{user_to_delete.id}"
      }.to change(User, :count).by(-1)
      expect(response).to redirect_to(admin_users_path)
    end
  end
end 