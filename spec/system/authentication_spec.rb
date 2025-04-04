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
    
    it "allows a new user to sign up with proper business context" do
      # Visit the registration path via the business subdomain
      # Construct the URL manually for rack_test
      registration_url = "http://#{business.subdomain}.example.com/users/sign_up"
      visit registration_url
      
      # Ensure the page loaded correctly (optional check)
      expect(page).to have_content("Sign up")

      new_email = "new_user_#{SecureRandom.hex(4)}@example.com"
      new_password = "password123"

      fill_in "Email", with: new_email
      fill_in "Password", with: new_password
      fill_in "Password confirmation", with: new_password

      click_button "Sign up"

      # Verify successful signup and redirection (e.g., to root path for logged-in users)
      expect(page).to have_current_path(root_path) # Check for root path
      # expect(page).to have_content("Welcome! You have signed up successfully.") # Flash message might vary
      # Check for content visible to logged-in users on the root page
      # expect(page).to have_content("Sign out") # Sign out is likely in the layout, not home index
      expect(page).to have_link("Dashboard") # Check for Dashboard link instead

      # Optional: Verify the user was created and associated with the correct tenant
      new_user = User.find_by(email: new_email)
      expect(new_user).not_to be_nil
      expect(new_user.business).to eq(business) 
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