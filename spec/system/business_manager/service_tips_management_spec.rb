require 'rails_helper'

RSpec.describe "Service Tips Management", type: :system do
  include_context 'setup business context'

  before do
    driven_by(:rack_test)
    login_as(manager, scope: :user)
    switch_to_subdomain(business.subdomain)
    Rails.application.reload_routes!
  end

  context "when creating a new service" do
    scenario "manager can enable tips for a new service" do
      visit business_manager_services_path

      click_link "New Service"

      fill_in "Name", with: "Premium Massage"
      fill_in "Description", with: "Relaxing full body massage"
      fill_in "Duration (minutes)", with: "90"
      fill_in "Price", with: "120.00"
      check "Enable tips"
      check "Active"

      click_button "Create Service"

      expect(page).to have_content("Service was successfully created")
      
      service = Service.last
      expect(service.tips_enabled).to be true
    end

    scenario "manager can create a service without tips enabled" do
      visit business_manager_services_path

      click_link "New Service"

      fill_in "Name", with: "Basic Consultation"
      fill_in "Description", with: "Initial consultation"
      fill_in "Duration (minutes)", with: "30"
      fill_in "Price", with: "50.00"
      # Don't check "Enable tips"
      check "Active"

      click_button "Create Service"

      expect(page).to have_content("Service was successfully created")
      
      service = Service.last
      expect(service.tips_enabled).to be false
    end
  end

  context "when editing an existing service" do
    let!(:service) { create(:service, business: business, name: "Test Service", tips_enabled: false) }

    scenario "manager can enable tips for an existing service" do
      visit edit_business_manager_service_path(service)

      check "Enable tips"
      click_button "Update Service"

      expect(page).to have_content("Service was successfully updated")
      
      service.reload
      expect(service.tips_enabled).to be true
    end

    scenario "manager can disable tips for an existing service" do
      service.update!(tips_enabled: true)
      
      visit edit_business_manager_service_path(service)

      uncheck "Enable tips"
      click_button "Update Service"

      expect(page).to have_content("Service was successfully updated")
      
      service.reload
      expect(service.tips_enabled).to be false
    end
  end

  context "form validation and UI" do
    scenario "tips checkbox is visible and properly labeled" do
      visit new_business_manager_service_path

      expect(page).to have_field("Enable tips", type: "checkbox")
      expect(page).to have_content("Enable tips")
    end

    scenario "tips checkbox state is preserved when editing" do
      service = create(:service, business: business, tips_enabled: true)
      
      visit edit_business_manager_service_path(service)

      expect(page).to have_checked_field("Enable tips")
    end
  end
end 