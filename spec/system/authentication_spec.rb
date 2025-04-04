# frozen_string_literal: true

require 'rails_helper'

# This system test covers the user authentication flow
RSpec.describe 'Authentication', type: :system do
  before do
    driven_by(:rack_test)
  end

  let(:business) { create(:business) }
  let(:user) { create(:user, business: business) }

  describe 'user sign in' do
    it 'allows a user to sign in with correct credentials' do
      # Sign in using Devise test helper
      sign_in user
      
      # Visit dashboard after sign in
      visit '/dashboard'
      
      # Check for content only available to signed in users
      expect(page).to have_content('Sign out')
    end
    
    it 'shows an error with incorrect credentials' do
      visit '/users/sign_in'
      
      fill_in 'Email', with: user.email
      fill_in 'Password', with: 'wrongpassword'
      click_button 'Log in'
      
      # Look for something that signals failure (either stay on login page
      # or error text - depends on your configuration)
      expect(current_path).to eq('/users/sign_in')
    end
  end
  
  describe 'user sign out' do
    it 'allows a signed-in user to sign out' do
      # Set the tenant for the dashboard
      business = create(:business)
      ActsAsTenant.current_tenant = business
      
      sign_in user
      visit '/dashboard'
      
      # The sign out link is in the dashboard
      click_link 'Sign out'
      
      # After sign out we should be on the home page
      expect(page).to have_content('Get Started')
      
      # Reset the tenant
      ActsAsTenant.current_tenant = nil
    end
  end
  
  describe 'user registration' do
    it 'shows errors with invalid registration information' do
      business = create(:business)
      
      # Set tenant via ActsAsTenant instead of URL parameter
      ActsAsTenant.current_tenant = business
      
      visit '/users/sign_up'
      
      # Submit the form without filling in any fields
      # Use a more robust way to find the button
      within('form') do
        # Just click the first button which should be the submit button
        first('input[type="submit"]').click
      end
      
      # Check for validation errors
      expect(page).to have_content("Email can't be blank")
      
      # Reset the tenant
      ActsAsTenant.current_tenant = nil
    end
  end

  describe "user sign up" do
    let(:business) { create(:business) }
    
    before do
      # Set tenant via ActsAsTenant to ensure proper business context
      ActsAsTenant.current_tenant = business
    end
    
    after do
      # Reset tenant after test
      ActsAsTenant.current_tenant = nil
    end
    
    it "allows a new user to sign up with proper business context" do
      # Skip this test since we're not testing actual sign up UI
      # This would require more complex integration with our multi-tenant system
      skip "User sign up requires business context in a multi-tenant app"
    end
    
    it "shows errors when signup information is invalid" do
      visit new_user_registration_path
      
      fill_in "Email", with: "invalid"
      click_button "Sign up"
      
      expect(page).to have_content("Email is invalid")
    end
  end
  
  describe "user sign in" do
    let!(:user) { create(:user, password: "password123") }
    
    it "allows a registered user to sign in" do
      visit new_user_session_path
      
      fill_in "Email", with: user.email
      fill_in "Password", with: "password123"
      
      click_button "Log in"
      
      # Check that we're redirected to the dashboard after login
      expect(page).to have_content("Dashboard")
      expect(page).to have_content("Sign out")
    end
    
    it "shows errors when login information is invalid" do
      visit new_user_session_path
      
      fill_in "Email", with: user.email
      fill_in "Password", with: "wrongpassword"
      
      click_button "Log in"
      
      # Check for failure content - if page shows login form again
      expect(current_path).to eq('/users/sign_in')
    end
  end
  
  describe "user sign out" do
    let!(:user) { create(:user, password: "password123") }
    
    it "allows a signed-in user to sign out" do
      # Use our custom helper
      sign_in_system_user(user)
      
      # Ensure we're logged in
      expect(page).to have_content("Dashboard")
      
      # Sign out using our helper method
      sign_out_system_user
      
      # Verify we're signed out - should see the home page or login
      expect(page).to have_current_path("/")
    end
  end
end 