# frozen_string_literal: true

# Helper module for Devise authentication in system tests
module DeviseHelpers
  # Sign in a user in system tests
  def sign_in_system_user(user = nil)
    @user = user || create(:user)
    visit new_user_session_path
    fill_in "Email", with: @user.email
    fill_in "Password", with: "password123"
    click_button "Log in"
    @user
  end
  
  # Sign out a user in system tests
  def sign_out_system_user
    click_link "Sign out"
  end

  def sign_out
    # Turbo uses data-turbo-method for delete requests
    if has_link?('Sign out', exact: true)
      click_link 'Sign out'
    elsif has_button?('Sign out', exact: true)
      click_button 'Sign out'
    else
      fail "Could not find sign out link or button"
    end
  end
end

# Include these helpers in the RSpec configuration
RSpec.configure do |config|
  config.include DeviseHelpers, type: :system
  config.include DeviseHelpers, type: :feature
end 