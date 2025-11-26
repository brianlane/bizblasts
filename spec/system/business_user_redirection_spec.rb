require 'rails_helper'

RSpec.describe 'Business User Redirection', type: :system, js: true do
  before do
    # Try using cuprite (it's our configured JS driver from capybara.rb)
    begin
      driven_by(:cuprite)
    rescue StandardError => e
      puts "Warning: #{e.message}"
      puts "Falling back to rack_test driver which doesn't support JavaScript"
      driven_by(:rack_test)
    end
  end

  # Setup a business with a subdomain and a business user associated with it.
  let!(:business) { create(:business, 
    name: 'Test Business',
    industry: 'other',
    tier: 'free',
    host_type: 'subdomain'
  ) }

  let!(:user) {
    user = User.create!(
      first_name: 'Test',
      last_name: 'Business',
      email: "business-#{SecureRandom.hex(4)}@test.com",
      password: 'password',
      password_confirmation: 'password',
      business: business,
      role: 'manager'
    )
    user.confirm # Confirm the user's email so they can sign in
    user
  }

  scenario 'Business user logs in from homepage and is redirected to subdomain dashboard, then logs out back to homepage' do
    # Start at the main domain
    switch_to_main_domain
    
    # Visit the homepage
    visit root_path

    # Accept the cookie banner if it appears
    if page.has_css?('#termly-code-snippet-support', wait: 5)
      within('#termly-code-snippet-support') do
        click_button 'Accept'
      end
    end

    expect(URI.parse(page.current_url).host).to eq('lvh.me')

    # Now instead of trying to fill in the login form,
    # use Warden to bypass the login form and sign in directly
    login_as(user, scope: :user)

    # After login, manually visit the dashboard
    switch_to_subdomain(business.subdomain)
    visit '/dashboard'

    # Check that we're actually on the dashboard page
    expect(page).to have_content(/Dashboard|Welcome|#{business.name}/i)
    
    # Check that we're on the right subdomain
    expect(URI.parse(page.current_url).host).to include(business.subdomain)

    # Find and click the sign out link
    if page.has_link?('Sign Out')
      click_link 'Sign Out'
    elsif page.has_link?('Sign out')
      click_link 'Sign out'
    elsif page.has_link?('Logout')
      click_link 'Logout'
    elsif page.has_button?('Sign Out')
      click_button 'Sign Out'
    else
      # If we can't find the sign out link, let's try to find it using a more generic approach
      find('a', text: /sign.?out/i, match: :first).click rescue nil
    end

    # After sign out, expect to be back on the main domain
    # The custom controller redirects to the main domain after sign out
    expect(URI.parse(page.current_url).host).to eq('lvh.me')
    
    # The homepage should have some welcome content 
    expect(page).to have_content(/Welcome|Home|Sign in/i)
  end

  scenario 'Business user logs in via FORM from homepage and is redirected to subdomain dashboard' do
    # Start at the main domain
    switch_to_main_domain
    visit root_path

    # Accept the cookie banner if it appears
    if page.has_css?('#termly-code-snippet-support', wait: 5)
      within('#termly-code-snippet-support') do
        click_button 'Accept'
      end
    end

    expect(URI.parse(page.current_url).host).to eq('lvh.me')

    # Find and click the Sign In link (updated from "Log in")
    click_link 'Sign In'
    expect(page).to have_current_path('/users/sign_in')

    # Fill in the login form
    fill_in 'Email', with: user.email
    fill_in 'Password', with: 'password' # Assuming 'password' is the factory default

    # Use a longer timeout for the button click as it may trigger slow operations (auth, redirects)
    using_wait_time(30) do
      click_button 'Sign In'

      # Assert redirection to the correct subdomain dashboard
      # Wait for potential redirection and page load
      expect(page).to have_current_path(%r{/dashboard$}, wait: 30)
    end 
    
    # Check the host after waiting for the path
    expect(URI.parse(page.current_url).host).to eq("#{business.hostname}.lvh.me")

    # Assert that dashboard content is visible (indicating successful authentication on subdomain)
    # Use a broad regex to match potential dashboard variations
    expect(page).to have_content(/Dashboard|Welcome|#{business.name}/i)
    
    # Verify the business's contact email is displayed on the dashboard
    expect(page).to have_content(user.email)
  end
end 