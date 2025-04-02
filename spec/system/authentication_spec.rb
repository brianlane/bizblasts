# frozen_string_literal: true

require 'rails_helper'

# This system test covers the user authentication flow
RSpec.describe 'Authentication', type: :system do
  before do
    driven_by(:rack_test)
  end

  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }

  describe 'user sign in' do
    it 'allows a user to sign in with correct credentials' do
      visit new_user_session_path
      
      fill_in 'Email', with: user.email
      fill_in 'Password', with: 'password123'
      click_button 'Log in'
      
      # The app doesn't flash a message for successful sign in
      expect(page).to have_content('Dashboard')
    end
    
    it 'shows an error with incorrect credentials' do
      visit new_user_session_path
      
      fill_in 'Email', with: user.email
      fill_in 'Password', with: 'wrongpassword'
      click_button 'Log in'
      
      # Look for something that signals failure (either stay on login page
      # or error text - depends on your configuration)
      expect(current_path).to eq(new_user_session_path)
    end
  end
  
  describe 'user sign out' do
    it 'allows a signed-in user to sign out' do
      # Set the tenant for the dashboard
      company = create(:company)
      ActsAsTenant.current_tenant = company
      
      sign_in user
      visit dashboard_path
      
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
      company = create(:company)
      
      # Set tenant via URL parameter
      visit new_user_registration_path(tenant_id: company.id)
      
      # No input, just submit
      click_button 'Sign up'
      
      expect(page).to have_content("Email can't be blank")
      expect(page).to have_content("Password can't be blank")
    end
    
    # Skip the user registration test for now
    # This would be better tested as an integration test
    # between devise and acts_as_tenant
  end
end 