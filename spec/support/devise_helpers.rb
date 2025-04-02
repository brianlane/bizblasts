# frozen_string_literal: true

# Helper to click on sign out links in system tests
module DeviseHelpers
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