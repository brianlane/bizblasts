require 'rails_helper'

RSpec.describe "Estimate flow", type: :system do
  let(:business) { create(:business) }
  let(:manager) { create(:user, :manager, business: business) }

  before do
    driven_by(:rack_test)
    Capybara.app_host = "http://#{business.subdomain}.lvh.me"
    sign_in manager
  end

  after do
    Capybara.app_host = nil
  end

  it "allows a business manager to create and send an estimate for a new customer" do
    visit business_manager_dashboard_path
    click_on "Estimates"
    click_on "New Estimate"

    # Open the custom customer dropdown
    find('.customer-dropdown-button').click
    # Select "Create new customer"
    find('.customer-option[data-item-id="new"]').click

    # Fill in new customer details
    within '#customer-details' do
      fill_in "First Name", with: "John", match: :first
      fill_in "Last Name", with: "Doe", match: :first
      fill_in "Email", with: "john.doe@example.com", match: :first
      fill_in "Phone", with: "555-1234", match: :first
      fill_in "Address", with: "123 Main St", match: :first
    end

    # The main form also has address fields for the estimate itself.
    fill_in "City", with: "Anytown"
    fill_in "State", with: "CA"
    fill_in "Zip", with: "12345"

    # Fill in estimate details
    fill_in "Proposed start time", with: Time.current + 5.days
    fill_in "Internal notes", with: "This is a test estimate."
    fill_in "Required deposit", with: "27.50"

    # Add a line item
    within first(".estimate_item_fields") do
      fill_in "Description", with: "Lawn Mowing"
      fill_in "Qty", with: "1"
      fill_in "Cost rate", with: "50"
      fill_in "Tax rate", with: "10"
    end

    click_on "Create Estimate"

    # Verify estimate was created
    expect(page).to have_content("Estimate created.")
    expect(page).to have_content("John Doe")
    expect(page).to have_content("$50.00") # Subtotal
    expect(page).to have_content("$5.00") # Tax
    expect(page).to have_content("$55.00") # Total
    expect(page).to have_content("$27.50") # Deposit
    expect(page).to have_content("draft") # Initial status

    # Send the estimate
    click_on "Send to Customer"
    expect(page).to have_content("Estimate sent to customer.")
    expect(page).to have_content("sent") # Status updated
  end
end 