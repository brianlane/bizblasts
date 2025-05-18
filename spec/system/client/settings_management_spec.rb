# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Client Settings Management", type: :system do
  let!(:client_user) { create(:user, :client, email: 'client@example.com', password: 'password123', first_name: 'OriginalFirst', last_name: 'OriginalLast') }

  before do
    driven_by(:rack_test) # Use rack_test driver which doesn't need a real server
    # Create a default business if navigation or views depend on it.
    # create(:business)
    sign_in client_user
    visit client_settings_path
  end

  it "allows a client to view their settings page" do
    expect(page).to have_content("My Settings")
    expect(page).to have_field("user_first_name", with: client_user.first_name)
    expect(page).to have_field("user_email", with: client_user.email)
  end

  it "allows a client to update their profile information" do
    fill_in "First name", with: "UpdatedFirst"
    fill_in "Last name", with: "UpdatedLast"
    fill_in "Phone", with: "0987654321"
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
    fill_in "Current password", with: "wrongpassword"
    fill_in "New Password", with: "newsecurepassword"
    fill_in "Confirm New Password", with: "newsecurepassword"
    click_button "Save Settings"

    expect(page).to have_content("Failed to update password")
    expect(page).to have_content("Current password is invalid") # Devise error message
  end
  
  it "shows errors for mismatched new passwords" do
    fill_in "Current password", with: "password123"
    fill_in "New Password", with: "newsecurepassword"
    fill_in "Confirm New Password", with: "mismatchpassword"
    click_button "Save Settings"

    expect(page).to have_content("Failed to update password")
    expect(page).to have_content("Password confirmation doesn't match Password") # Devise error message
  end

  it "allows a client to update their notification preferences" do
    check "Email Booking Confirmations"
    uncheck "SMS Booking Reminders"
    check "Email Order Updates (for products)"
    uncheck "SMS Order Updates (for products)"
    check "Email Promotional Offers & News"
    uncheck "SMS Promotional Offers"

    click_button "Save Settings"

    expect(page).to have_content("Profile settings updated successfully.")
    # Don't check specific notification_preferences values as we've already done that in the request spec
  end
end 