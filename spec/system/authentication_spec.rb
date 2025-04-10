# frozen_string_literal: true

require 'rails_helper'

# This system test covers the user authentication flow
RSpec.describe 'Authentication', type: :system do
  before do
    driven_by(:rack_test)
  end

  let(:business) { create(:business) }
  # Attempt 2: Use manager role to see if it fixes sign-in/out flow
  let(:user) { create(:user, :manager, business: business) }

  describe 'user sign in' do
    it 'allows a user to sign in with correct credentials' do
      # Sign in using Devise test helper
      sign_in user
      
      # Let's try visiting the dashboard path again now that the client is associated
      visit dashboard_path # Assuming this is the correct path after login
      
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
      sign_in user
      visit dashboard_path # Try dashboard again
      
      # Assuming sign out link is available on root path layout for logged-in users
      click_link 'Sign out'
      
      # After sign out we should be on the home page
      expect(page).to have_content('Get Started')
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
      # Check for content indicating successful login, e.g., user email in navbar or sign out link
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
    # Attempt 2: Use manager role
    let!(:business_for_manager) { create(:business) }
    let!(:user) { create(:user, :manager, business: business_for_manager, password: "password123") }
    
    it "allows a registered user to sign in" do
      visit new_user_session_path
      
      fill_in "Email", with: user.email
      fill_in "Password", with: "password123"
      
      click_button "Log in"
      
      # Check that we're redirected to the dashboard after login
      expect(page).to have_current_path(dashboard_path) # Expect dashboard path
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
    # Attempt 2: Use manager role
    let!(:business_for_manager) { create(:business) }
    let!(:user) { create(:user, :manager, business: business_for_manager, password: "password123") }
    
    it "allows a signed-in user to sign out" do
      # Use our custom helper
      sign_in_system_user(user)
      
      # Ensure we're logged in
      visit dashboard_path # Go to dashboard first
      expect(page).to have_current_path(dashboard_path)
      
      # Sign out using our helper method
      sign_out_system_user
      
      # Verify we're signed out - should see the home page or login
      expect(page).to have_current_path("/")
    end
  end
end 