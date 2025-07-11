# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Client Settings Management", type: :system do
  let!(:client_user) { create(:user, :client, email: 'client@example.com', password: 'password123', first_name: 'OriginalFirst', last_name: 'OriginalLast') }

  before do
    driven_by(:rack_test) # Use rack_test driver which doesn't need a real server
    
    # Configure Capybara for main domain (not subdomain)
    Capybara.app_host = "http://www.example.com"
    
    # Make sure we're on the main domain, not a subdomain
    ActsAsTenant.current_tenant = nil
    
    # Sign in the client user
    sign_in client_user
    
    # Visit the client settings path
    visit client_settings_path
  end

  it "allows a client to view their settings page" do
    expect(page).to have_content("My Settings")
    expect(page).to have_field("user[first_name]", with: client_user.first_name)
    expect(page).to have_field("user[email]", with: client_user.email)
  end

  it "allows a client to update their profile information" do
    fill_in "user[first_name]", with: "UpdatedFirst"
    fill_in "user[last_name]", with: "UpdatedLast"
    fill_in "user[phone]", with: "0987654321"
    click_button "Save Settings"

    expect(page).to have_content("Profile settings updated successfully.")
    client_user.reload
    expect(client_user.first_name).to eq("UpdatedFirst")
    expect(client_user.last_name).to eq("UpdatedLast")
    expect(client_user.phone).to eq("0987654321")
  end

  # Skip password tests that involve Sign Out and Sign In
  # Those would be better suited for a test with a real browser if needed

  it "shows errors for invalid password change (e.g., wrong current password)" do
    # Target the first form on the page (profile update form)
    within(first('form')) do
      fill_in "user[current_password]", with: "wrongpassword"
      fill_in "user[password]", with: "newsecurepassword"
      fill_in "user[password_confirmation]", with: "newsecurepassword"
      click_button "Save Settings"
    end

    expect(page).to have_content("Failed to update password")
    expect(page).to have_content("Current password is invalid") # Devise error message
  end
  
  it "shows errors for mismatched new passwords" do
    # Target the first form on the page (profile update form)
    within(first('form')) do
      fill_in "user[current_password]", with: "password123"
      fill_in "user[password]", with: "newsecurepassword"
      fill_in "user[password_confirmation]", with: "mismatchpassword"
      click_button "Save Settings"
    end

    expect(page).to have_content("Failed to update password")
    expect(page).to have_content("Password confirmation doesn't match Password") # Devise error message
  end

  it "allows a client to update their notification preferences" do
    # Use more reliable name-based selectors for checkboxes
    check "user[notification_preferences][email_booking_confirmation]"
    uncheck "user[notification_preferences][sms_booking_reminder]"
    check "user[notification_preferences][email_order_updates]"
    uncheck "user[notification_preferences][sms_order_updates]"
    check "user[notification_preferences][email_promotions]"
    uncheck "user[notification_preferences][sms_promotions]"

    click_button "Save Settings"

    expect(page).to have_content("Profile settings updated successfully.")
    # Don't check specific notification_preferences values as we've already done that in the request spec
  end

  it "shows the 'Unsubscribed Successfully' banner and disables notification toggles if globally unsubscribed" do
    client_user.update!(unsubscribed_at: Time.current)
    visit client_settings_path
    expect(page).to have_content("Unsubscribed Successfully")
    expect(page).to have_content("You have globally unsubscribed from all marketing and notification emails")
    expect(page).to have_button("Resubscribe")
    # All notification checkboxes should be disabled
    within('fieldset[disabled]') do
      expect(page).to have_unchecked_field("user[notification_preferences][email_booking_confirmation]", disabled: true)
      expect(page).to have_unchecked_field("user[notification_preferences][email_order_updates]", disabled: true)
      expect(page).to have_unchecked_field("user[notification_preferences][email_promotions]", disabled: true)
    end
  end
end 