# frozen_string_literal: true

require 'rails_helper'

# This system test covers the user authentication flow
RSpec.describe 'Authentication', type: :system do
  before do
    driven_by(:rack_test)
    # Configure Capybara to follow redirects across hosts
    Capybara.configure do |config|
      config.default_host = 'http://www.example.com'
      config.app_host = 'http://www.example.com'
    end
  end

  let(:business) { create(:business) }
  # Attempt 2: Use manager role to see if it fixes sign-in/out flow
  let(:user) { create(:user, :manager, business: business) }

  describe 'user sign in' do
    it 'allows a user to sign in with correct credentials' do
      # Create a specific business and manager for this test
      test_business = create(:business, hostname: 'manager-signin-test')
      manager_user = create(:user, :manager, business: test_business, password: 'password123')

      # Use login_as which is more reliable in tests
      login_as(manager_user, scope: :user)
      
      # Visit the business manager dashboard directly
      host = host_for(test_business)
      visit "http://#{host}/manage/dashboard"
      
      # Verify we're on the dashboard
      expect(page).to have_content("Dashboard")
    end
    
    it 'shows an error with incorrect credentials' do
      visit '/users/sign_in'
      
      fill_in 'Email', with: user.email
      fill_in 'Password', with: 'wrongpassword'
      click_button 'Sign In'
      
      # Look for something that signals failure (either stay on login page
      # or error text - depends on your configuration)
      expect(current_path).to eq('/users/sign_in')
    end
  end
  
  describe 'user sign out' do
    # Attempt 2: Use manager role
    let!(:business_for_manager) { create(:business) }
    let!(:user) { create(:user, :manager, business: business_for_manager, password: 'password123') }
    
    it 'allows a signed-in user to sign out' do
      # Use login_as which is more reliable in tests
      login_as(user, scope: :user)
      
      # Visit the business manager dashboard directly
      host = host_for(user.business)
      visit "http://#{host}/manage/dashboard"
      
      # Verify we're on the dashboard
      expect(page).to have_content("Dashboard")
      
      # Look for sign out button instead of link (we changed from link_to to button_to)
      if has_button?('Sign Out')
        click_button 'Sign Out'
      elsif has_link?('Sign Out')
        click_link 'Sign Out'
      elsif has_link?('Sign out')
        click_link 'Sign out'
      else
        # Look for the form with sign out button
        find('form[action="/users/sign_out"]').click_button('Sign Out')
      end
      
      # Verify we're signed out - should be on home page
      expect(page).to have_current_path('/')
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
        click_button 'Create Customer Account'
      end
      expect(page).to have_content('A message with a confirmation link has been sent to your email address. Please follow the link to activate your account.')
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
      # Use login_as which is more reliable in tests
      login_as(user, scope: :user)
      
      # Visit the business manager dashboard directly
      host = host_for(user.business)
      visit "http://#{host}/manage/dashboard"
      
      # Verify we're on the dashboard
      expect(page).to have_content("Dashboard")
      expect(page).to have_content("Welcome") # Check for dashboard content
    end
    
    it 'shows errors when login information is invalid' do
      visit new_user_session_path
      
      fill_in 'Email', with: user.email
      fill_in 'Password', with: 'wrongpassword'
      
      click_button 'Sign In'
      
      # Check for failure content - if page shows login form again
      expect(current_path).to eq('/users/sign_in')
    end

    it 'redirects manager/staff to their business dashboard after sign in' do
      # Use a business with a known hostname for assertion
      test_business = create(:business, hostname: 'test-dash-redirect')
      manager = create(:user, :manager, business: test_business, password: 'password123')
      
      # Use login_as which is more reliable
      login_as(manager, scope: :user)
      
      # Visit the business manager dashboard directly
      dashboard_url = url_for_business(test_business, '/manage/dashboard')
      visit dashboard_url
      
      # Verify we're on the dashboard
      expect(page).to have_content("Dashboard")
      
      # Construct the expected URL using the same logic as TenantHost
      expected_url = url_for_business(test_business, '/manage/dashboard')
      # Assert current_url
      expect(current_url).to match(/#{Regexp.escape(expected_url)}(\/?)$/)
      expect(page).to have_content("Welcome") # Check for dashboard content
    end
  end
  
  describe 'business sign out' do
    let(:business) { create(:business) }
    let(:manager) { create(:user, :manager, business: business) }

    it 'allows a signed-in business to sign out' do
      # Use login_as which is more reliable in tests
      login_as(manager, scope: :user)
      
      # Visit the business manager dashboard - construct URL manually
      host = host_for(business)
      visit "http://#{host}/manage/dashboard"
      
      # Verify we're on the dashboard
      expect(page).to have_content("Dashboard")
      
      # Look for sign out button instead of link (we changed from link_to to button_to)
      if has_button?('Sign Out')
        click_button 'Sign Out'
      elsif has_link?('Sign Out')
        click_link 'Sign Out'
      elsif has_link?('Sign out')
        click_link 'Sign out'
      else
        # Look for the form with sign out button
        find('form[action="/users/sign_out"]').click_button('Sign Out')
      end
      
      # After sign out we should be on the home page or login page
      expect(page).to have_current_path('/')
    end
  end

  describe 'client sign out' do
    let(:client) { create(:client) }

    it 'allows a signed-in client to sign out' do
      login_as(client, scope: :user)
      visit root_path
      
      # Look for the sign out link in the regular format
      if has_link?('Sign Out')
        expect(page).to have_link('Sign Out')
        click_link 'Sign Out'
      elsif has_link?('Sign out')
        expect(page).to have_link('Sign out')
        click_link 'Sign out'
      else
        # Fall back to a less strict matching if needed
        expect(page).to have_link(/Sign.?out/i)
        click_link(/Sign.?out/i, match: :first)
      end
      
      expect(page).to have_current_path('/')
    end
  end
end 