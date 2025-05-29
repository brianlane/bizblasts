# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Client Account Deletion", type: :system do
  let(:client_user) { create(:user, :client, email: 'client@example.com', password: 'password123') }
  let(:business) { create(:business) }

  before do
    driven_by(:rack_test)
    Capybara.app_host = "http://www.example.com"
    ActsAsTenant.current_tenant = nil
    sign_in client_user
  end

  context "account deletion flow" do
    it "shows the account deletion section in settings" do
      visit client_settings_path
      
      expect(page).to have_content("Delete Account")
      expect(page).to have_content("This action cannot be undone")
      expect(page).to have_field("user[current_password]")
      expect(page).to have_field("user[confirm_deletion]")
      expect(page).to have_button("Delete My Account")
    end

    it "requires current password for deletion" do
      visit client_settings_path
      
      fill_in "user[confirm_deletion]", with: "DELETE"
      click_button "Delete My Account"
      
      expect(page).to have_content("Current password is required")
      expect(User.exists?(client_user.id)).to be true
    end

    it "requires deletion confirmation text" do
      visit client_settings_path
      
      fill_in "user[current_password]", with: "password123"
      click_button "Delete My Account"
      
      expect(page).to have_content("must type DELETE")
      expect(User.exists?(client_user.id)).to be true
    end

    it "validates current password" do
      visit client_settings_path
      
      fill_in "user[current_password]", with: "wrongpassword"
      fill_in "user[confirm_deletion]", with: "DELETE"
      click_button "Delete My Account"
      
      expect(page).to have_content("Current password is incorrect")
      expect(User.exists?(client_user.id)).to be true
    end

    it "successfully deletes account with valid inputs" do
      visit client_settings_path
      
      fill_in "user[current_password]", with: "password123"
      fill_in "user[confirm_deletion]", with: "DELETE"
      
      expect {
        click_button "Delete My Account"
      }.to change(User, :count).by(-1)
      
      expect(page).to have_content("Your account has been deleted")
      expect(current_path).to eq(root_path)
    end

    it "handles client with business associations" do
      create(:client_business, user: client_user, business: business)
      
      visit client_settings_path
      
      fill_in "user[current_password]", with: "password123"
      fill_in "user[confirm_deletion]", with: "DELETE"
      
      expect {
        click_button "Delete My Account"
      }.to change(User, :count).by(-1)
       .and change(ClientBusiness, :count).by(-1)
      
      # Business should remain
      expect(Business.exists?(business.id)).to be true
      expect(page).to have_content("Your account has been deleted")
    end
  end

  context "account deletion warnings" do
    before do
      # Create some associated data
      create(:client_business, user: client_user, business: business)
    end

    it "shows warnings about data that will be affected" do
      visit client_settings_path
      
      expect(page).to have_content("Deleting your account will:")
      expect(page).to have_content("Remove you from all business relationships")
      expect(page).to have_content("Your booking history will be preserved")
    end
  end

  context "with JavaScript enabled" do
    before do
      driven_by(:selenium_headless)
    end

    it "shows confirmation dialog before deletion" do
      visit client_settings_path
      
      fill_in "user[current_password]", with: "password123"
      fill_in "user[confirm_deletion]", with: "DELETE"
      
      # Dismiss the confirmation dialog
      dismiss_confirm do
        click_button "Delete My Account"
      end
      
      # Account should still exist
      expect(User.exists?(client_user.id)).to be true
    end

    it "proceeds with deletion when confirmed" do
      visit client_settings_path
      
      fill_in "user[current_password]", with: "password123"
      fill_in "user[confirm_deletion]", with: "DELETE"
      
      # Accept the confirmation dialog
      accept_confirm do
        click_button "Delete My Account"
      end
      
      expect(page).to have_content("Your account has been deleted")
    end
  end
end 