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
      expect(page).to have_content("Once you delete your account, there is no going back")
      within('.deletion-form') do
        expect(page).to have_field("user[current_password]")
        expect(page).to have_field("user[confirm_deletion]")
        expect(page).to have_button("Delete My Account")
      end
    end

    it "requires current password for deletion" do
      visit client_settings_path
      
      within('.deletion-form') do
        fill_in "user[confirm_deletion]", with: "DELETE"
        click_button "Delete My Account"
      end
      
      expect(page).to have_content("Current password is incorrect")
      expect(User.exists?(client_user.id)).to be true
    end

    it "requires deletion confirmation text" do
      visit client_settings_path
      
      within('.deletion-form') do
        fill_in "user[current_password]", with: "password123"
        click_button "Delete My Account"
      end
      
      expect(page).to have_content("must type DELETE")
      expect(User.exists?(client_user.id)).to be true
    end

    it "validates current password" do
      visit client_settings_path
      
      within('.deletion-form') do
        fill_in "user[current_password]", with: "wrongpassword"
        fill_in "user[confirm_deletion]", with: "DELETE"
        click_button "Delete My Account"
      end
      
      expect(page).to have_content("Current password is incorrect")
      expect(User.exists?(client_user.id)).to be true
    end

    it "successfully deletes account with valid inputs" do
      visit client_settings_path
      
      within('.deletion-form') do
        fill_in "user[current_password]", with: "password123"
        fill_in "user[confirm_deletion]", with: "DELETE"
        
        expect {
          click_button "Delete My Account"
        }.to change(User, :count).by(-1)
      end
      
      expect(page).to have_content("Your account has been deleted")
      expect(current_path).to eq(root_path)
    end

    it "handles client with business associations" do
      create(:client_business, user: client_user, business: business)
      
      visit client_settings_path
      
      within('.deletion-form') do
        fill_in "user[current_password]", with: "password123"
        fill_in "user[confirm_deletion]", with: "DELETE"
        
        expect {
          click_button "Delete My Account"
        }.to change(User, :count).by(-1)
         .and change(ClientBusiness, :count).by(-1)
      end
      
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
      expect(page).to have_content("Remove you from all businesses")
      expect(page).to have_content("Your booking history will not be preserved")
    end
  end
end 