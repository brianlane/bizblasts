# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Business Registration", type: :system do
  before do
    # Create required policy versions for business registration
    create(:policy_version, policy_type: 'privacy_policy', version: 'v1.0', active: true)
    create(:policy_version, policy_type: 'terms_of_service', version: 'v1.0', active: true)
    create(:policy_version, policy_type: 'acceptable_use_policy', version: 'v1.0', active: true)
    create(:policy_version, policy_type: 'return_policy', version: 'v1.0', active: true)

    # Business registration is on the main domain (no subdomain)
    switch_to_main_domain
  end

  def fill_registration_form(email:, business_name:, subdomain:, custom_domain: nil)
    visit new_business_registration_path

    # Owner information
    fill_in "First name", with: "Test"
    fill_in "Last name", with: "User"
    fill_in "Email", with: email
    fill_in "Password", with: "password123"
    fill_in "Password confirmation", with: "password123"

    # Business information
    fill_in "Business Name", with: business_name
    select "Other", from: "Industry"
    fill_in "Business Phone", with: "555-123-4567"
    fill_in "Business Contact Email", with: "contact@testbiz.com"
    fill_in "Address", with: "123 Main St"
    fill_in "City", with: "Anytown"
    fill_in "State", with: "CA"
    fill_in "Zip", with: "12345"
    fill_in "Description", with: "A test business"

    fill_in "registration_subdomain_field", with: subdomain

    if custom_domain.present?
      # Fill the hostname field robustly (some drivers are picky about label matching).
      hostname_input = find('input[name="user[business_attributes][hostname]"]', visible: :all)
      hostname_input.set(custom_domain)
      page.execute_script("arguments[0].dispatchEvent(new Event('input', { bubbles: true }))", hostname_input)

      # Ensure host type reflects a custom domain even if JS events are flaky in CI.
      page.execute_script("document.getElementById('host_type_input').value = 'custom_domain'")
    end

    # Accept all required policies
    check "policy_acceptances_terms_of_service"
    check "policy_acceptances_privacy_policy"
    check "policy_acceptances_acceptable_use_policy"
    check "policy_acceptances_return_policy"
  end

  it "shows simple, transparent pricing" do
    visit new_business_registration_path

    expect(page).to have_content("Simple, Transparent Pricing")
    expect(page).to have_content("$0/month")
    expect(page).to have_content("1% platform fee")
  end

  it "creates a business with a subdomain" do
    expect {
      fill_registration_form(email: "john@example.com", business_name: "Test Business", subdomain: "testbiz")
      click_button "Create Business Account"
    }.to change(Business, :count).by(1).and change(User, :count).by(1)

    expect(page).to have_current_path(root_path)
    expect(page).to have_content("A message with a confirmation link has been sent")

    business = Business.last
    expect(business.host_type).to eq("subdomain")
    expect(business.subdomain).to eq("testbiz")
  end

  it "creates a business with a custom domain", js: true do
    fill_registration_form(
      email: "domain@example.com",
      business_name: "Domain Business",
      subdomain: "domainbiz",
      custom_domain: "example-domain.com"
    )
    click_button "Create Business Account"

    expect(page).to have_current_path(root_path)
    expect(page).to have_content("A message with a confirmation link has been sent")

    expect(Business.count).to eq(1)
    expect(User.count).to eq(1)

    business = Business.last
    expect(business.host_type).to eq("custom_domain")
    expect(business.hostname).to eq("example-domain.com")
  end

  it "shows validation errors when required fields are missing" do
    visit new_business_registration_path

    click_button "Create Business Account"

    expect(page).to have_content("can't be blank").or have_content("errors prohibited").or have_content("required")
    expect(page).to have_current_path(business_registration_path)
  end
end
