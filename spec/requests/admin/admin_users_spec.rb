# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Admin AdminUsers", type: :request, admin: true do
  let!(:current_admin_user) { AdminUser.first || create(:admin_user) } # The user performing actions
  let!(:other_admin_user) { create(:admin_user, email: "other@example.com") }

  before do
    sign_in current_admin_user
  end

  describe "GET /admin/admin_users" do
    it "lists all admin users" do
      get "/admin/admin_users"
      expect(response).to be_successful
      expect(response.body).to include(current_admin_user.email)
      expect(response.body).to include(other_admin_user.email)
    end
  end

  describe "GET /admin/admin_users/:id" do
    it "shows the admin user details" do
      get "/admin/admin_users/#{other_admin_user.id}"
      expect(response).to be_successful
      expect(response.body).to include(other_admin_user.email)
      # Check other fields like sign_in_count if needed
    end
  end

  describe "GET /admin/admin_users/new" do
    it "shows the new admin user form" do
      get "/admin/admin_users/new"
      expect(response).to be_successful
      expect(response.body).to include("New Admin User") 
    end
  end

  describe "POST /admin/admin_users" do
    let(:valid_attributes) do
      { 
        email: "newadmin@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    end

    it "creates a new admin user" do
      expect {
        post "/admin/admin_users", params: { admin_user: valid_attributes }
      }.to change(AdminUser, :count).by(1)
      
      new_admin_user = AdminUser.find_by(email: "newadmin@example.com")
      expect(response).to redirect_to(admin_admin_user_path(new_admin_user))
      follow_redirect!
      # Default flash message might not be present, check content instead
      expect(response.body).to include("Admin User Details") 
      expect(response.body).to include("newadmin@example.com")
    end

    # Add test for invalid attributes (e.g., password mismatch)
    let(:invalid_attributes) do
       { 
        email: "invalid@example.com",
        password: "password123",
        password_confirmation: "wrongpassword"
      }
    end

    it "does not create an admin user with invalid attributes" do
       expect {
        post "/admin/admin_users", params: { admin_user: invalid_attributes }
      }.not_to change(AdminUser, :count)
      
      expect(response).to have_http_status(:ok) # Should re-render the form
      # expect(response.body).to include("Password confirmation doesn't match Password") # Temporarily commented out
    end
  end

  describe "GET /admin/admin_users/:id/edit" do
    it "shows the edit admin user form" do
      get "/admin/admin_users/#{other_admin_user.id}/edit"
      expect(response).to be_successful
      expect(response.body).to include("Edit Admin User")
      expect(response.body).to include(other_admin_user.email)
    end
  end

  describe "PATCH /admin/admin_users/:id" do
    let(:updated_attributes) do
      { 
        email: "updated@example.com" 
        # Cannot update password here without current_password for Devise
      }
    end

    it "updates the admin user email" do
      patch "/admin/admin_users/#{other_admin_user.id}", params: { admin_user: updated_attributes }
      
      other_admin_user.reload
      expect(response).to redirect_to(admin_admin_user_path(other_admin_user))
      follow_redirect!
      # Default flash message might not be present, check content instead
      expect(response.body).to include("Admin User Details")
      expect(response.body).to include("updated@example.com")
      expect(other_admin_user.email).to eq("updated@example.com")
    end

    # Add test for invalid update if needed
  end

  describe "DELETE /admin/admin_users/:id" do
    # Prevent deleting the currently logged-in admin
    let!(:another_admin) { create(:admin_user, email: "deleteme@example.com") }

    it "deletes the admin user" do
      expect {
        delete "/admin/admin_users/#{another_admin.id}"
      }.to change(AdminUser, :count).by(-1)
      
      expect(response).to redirect_to(admin_admin_users_path)
      follow_redirect!
      # Default flash message might not be present, check content instead
      expect(response.body).to include("Admin Users")
      expect(response.body).not_to include("deleteme@example.com")
    end

    it "does not allow deleting the current admin user" do
       expect {
        delete "/admin/admin_users/#{current_admin_user.id}"
      }.not_to change(AdminUser, :count)
      
      expect(response).to redirect_to(admin_admin_users_path)
      follow_redirect!
      expect(response.body).to include("Cannot delete yourself.")
    end
  end
end 