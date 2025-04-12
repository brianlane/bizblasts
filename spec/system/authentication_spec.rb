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
  
  describe 'client sign up' do
    it 'allows a new client to sign up' do
      visit new_client_registration_path
      within('form') do
        fill_in 'First name', with: 'New'
        fill_in 'Last name', with: 'Client'
        fill_in 'Email', with: 'newclient@example.com'
        fill_in 'Password', with: 'password'
        fill_in 'Password confirmation', with: 'password'
        click_button 'Sign up'
      end
      expect(page).to have_content('Welcome! You have signed up successfully.')
      expect(User.last.email).to eq('newclient@example.com')
      expect(User.last.client?).to be true
    end
    
    it 'shows errors with invalid registration information' do
      visit new_client_registration_path
      within('form') do
        # Just click the first button which should be the submit button
        first('input[type="submit"]').click 
      end
      expect(page).to have_content('errors prohibited this user from being saved')
      expect(page).to have_content("Email can't be blank")
      expect(page).to have_content("Password can't be blank")
    end
  end
  
  describe 'user sign in' do
    # Attempt 2: Use manager role
    let!(:business_for_manager) { create(:business) }
    let!(:user) { create(:user, :manager, business: business_for_manager, password: 'password123') }
    
    it 'allows a registered user to sign in' do
      visit new_user_session_path
      
      fill_in 'Email', with: user.email
      fill_in 'Password', with: 'password123'
      
      click_button 'Log in'
      
      # Check that we're redirected to the dashboard after login
      expect(page).to have_current_path(dashboard_path) # Expect dashboard path
      expect(page).to have_content('Sign out')
    end
    
    it 'shows errors when login information is invalid' do
      visit new_user_session_path
      
      fill_in 'Email', with: user.email
      fill_in 'Password', with: 'wrongpassword'
      
      click_button 'Log in'
      
      # Check for failure content - if page shows login form again
      expect(current_path).to eq('/users/sign_in')
    end
  end
  
  describe 'user sign out' do
    # Attempt 2: Use manager role
    let!(:business_for_manager) { create(:business) }
    let!(:user) { create(:user, :manager, business: business_for_manager, password: 'password123') }
    
    it 'allows a signed-in user to sign out' do
      # Use our custom helper
      sign_in_system_user(user)
      
      # Ensure we're logged in
      visit dashboard_path # Go to dashboard first
      expect(page).to have_current_path(dashboard_path)
      
      # Sign out using our helper method
      sign_out_system_user
      
      # Verify we're signed out - should see the home page or login
      expect(page).to have_current_path('/')
    end
  end
end 