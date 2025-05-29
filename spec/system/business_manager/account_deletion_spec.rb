# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Business Manager Account Deletion", type: :system do
  let(:business) { create(:business, hostname: 'testbiz') }
  
  before do
    driven_by(:rack_test)
    ActsAsTenant.current_tenant = business
    Capybara.app_host = "http://testbiz.lvh.me"
  end

  context "staff member account deletion" do
    let(:staff_user) { create(:user, :staff, business: business, password: 'password123') }
    let!(:staff_member) { create(:staff_member, business: business, user: staff_user) }

    before do
      sign_in staff_user
    end

    it "shows the account deletion section in profile settings" do
      visit edit_business_manager_settings_profile_path
      
      expect(page).to have_content("Delete Account")
      expect(page).to have_content("Once you delete your account, there is no going back")
      within('.deletion-form') do
        expect(page).to have_field("user[current_password]")
        expect(page).to have_field("user[confirm_deletion]")
        expect(page).to have_button("Delete My Account")
      end
    end

    it "successfully deletes staff account" do
      visit edit_business_manager_settings_profile_path
      
      within('.deletion-form') do
        fill_in "user[current_password]", with: "password123"
        fill_in "user[confirm_deletion]", with: "DELETE"
        
        expect {
          click_button "Delete My Account"
        }.to change(User, :count).by(-1)
         .and change(StaffMember, :count).by(-1)
      end
      
      expect(page).to have_content("Your account has been deleted")
      expect(current_path).to eq(root_path)
    end

    it "shows warnings about future bookings" do
      create(:booking, 
        business: business, 
        staff_member: staff_member,
        start_time: 1.week.from_now
      )
      
      visit edit_business_manager_settings_profile_path
      
      expect(page).to have_content("You have 1 future booking")
      expect(page).to have_content("will be reassigned or cancelled")
    end
  end

  context "manager account deletion with other managers" do
    let(:manager_user) { create(:user, :manager, business: business, password: 'password123') }
    let!(:other_manager) { create(:user, :manager, business: business) }

    before do
      sign_in manager_user
    end

    it "successfully deletes manager account when other managers exist" do
      visit edit_business_manager_settings_profile_path
      
      within('.deletion-form') do
        fill_in "user[current_password]", with: "password123"
        fill_in "user[confirm_deletion]", with: "DELETE"
        
        expect {
          click_button "Delete My Account"
        }.to change(User, :count).by(-1)
      end
      
      expect(page).to have_content("Your account has been deleted")
      expect(Business.exists?(business.id)).to be true
    end
  end

  context "sole manager account deletion" do
    let(:manager_user) { create(:user, :manager, business: business, password: 'password123') }

    before do
      sign_in manager_user
    end

    it "shows business deletion warning for sole manager" do
      visit edit_business_manager_settings_profile_path
      
      expect(page).to have_content("Warning: You are the sole manager")
      expect(page).to have_content("This will also delete the business")
      within('.deletion-form') do
        expect(page).to have_field("user[delete_business]")
      end
    end

    it "prevents deletion without business deletion confirmation" do
      visit edit_business_manager_settings_profile_path
      
      within('.deletion-form') do
        fill_in "user[current_password]", with: "password123"
        fill_in "user[confirm_deletion]", with: "DELETE"
        
        expect {
          click_button "Delete My Account"
        }.not_to change(User, :count)
      end
      
      expect(page).to have_content("You are the sole manager")
      expect(User.exists?(manager_user.id)).to be true
    end

    it "deletes manager and business when business deletion is confirmed" do
      visit edit_business_manager_settings_profile_path
      
      within('.deletion-form') do
        fill_in "user[current_password]", with: "password123"
        fill_in "user[confirm_deletion]", with: "DELETE"
        check "user[delete_business]"
        
        expect {
          click_button "Delete My Account"
        }.to change(User, :count).by(-1)
         .and change(Business, :count).by(-1)
      end
      
      # The business and user have been successfully deleted
      # The flash message and redirect behavior are tested in request specs
      # since system tests can't reliably test cross-domain redirects after business deletion
    end

    it "shows detailed business deletion warnings" do
      # Create some business data
      create(:service, business: business)
      create(:tenant_customer, business: business)
      create(:booking, business: business)
      
      visit edit_business_manager_settings_profile_path
      
      expect(page).to have_content("Deleting the business will also delete:")
      expect(page).to have_content("All services")
      expect(page).to have_content("All customer data")
      expect(page).to have_content("All bookings")
    end
  end
end 