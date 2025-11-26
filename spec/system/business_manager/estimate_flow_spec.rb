require 'rails_helper'

RSpec.describe "Estimate flow", type: :system do
  let(:business) { create(:business, show_estimate_page: true) }
  let(:manager) { create(:user, :manager, business: business) }
  let!(:customer) { create(:tenant_customer, business: business, first_name: "John", last_name: "Doe", email: "john.doe@example.com") }
  let!(:service) { create(:service, business: business, name: "Lawn Mowing", price: 50) }

  before do
    driven_by(:rack_test)
    Capybara.app_host = "http://#{business.subdomain}.lvh.me"
    ActsAsTenant.current_tenant = business
    sign_in manager
  end

  after do
    Capybara.app_host = nil
    ActsAsTenant.current_tenant = nil
  end

  it "allows a business manager to create and send an estimate for an existing customer" do
    visit business_manager_dashboard_path
    click_on "Estimates"
    click_on "New Estimate"

    # Since rack_test doesn't execute JavaScript, directly set the hidden field for customer selection
    find('input[name="estimate[tenant_customer_id]"]', visible: false).set(customer.id)

    # Fill in estimate details
    fill_in "estimate_required_deposit", with: "27.50"

    # Fill in line item using input name attributes
    fill_in "estimate[estimate_items_attributes][0][description]", with: "Lawn Mowing Service"
    fill_in "estimate[estimate_items_attributes][0][qty]", with: "1"
    fill_in "estimate[estimate_items_attributes][0][cost_rate]", with: "50"
    fill_in "estimate[estimate_items_attributes][0][tax_rate]", with: "10"

    click_on "Create Estimate"

    # Verify estimate was created
    expect(page).to have_content("Estimate created")
    expect(page).to have_content("John Doe")
    expect(page).to have_content("$50.00") # Subtotal
    expect(page).to have_content("draft") # Initial status

    # Send the estimate
    click_on "Send to Customer"
    expect(page).to have_content("Estimate sent to customer")
    expect(page).to have_content("sent") # Status updated
  end
end 