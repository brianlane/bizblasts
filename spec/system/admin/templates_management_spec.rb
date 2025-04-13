require 'rails_helper'

RSpec.describe "Admin Template Management", type: :system, admin: true do
  let!(:admin_user) { create(:admin_user) }

  before do
    login_as(admin_user, scope: :admin_user)
  end

  context "Creating a new template", js: true do
    it "allows admin to create a template with pages" do
      visit new_admin_service_template_path
      # Wait for the form page to load
      expect(page).to have_field("Name", wait: 10)

      fill_in "Name", with: "Landscaping Basic"
      fill_in "Description", with: "Basic template for landscaping businesses"
      select "Landscaping", from: "Industry"
      select "Full website", from: "Template type"
      check "Active"

      structure_json = JSON.pretty_generate(
        pages: [
          { title: "Home", slug: "home", page_type: "home" },
          { title: "Services", slug: "services", page_type: "services" }
        ]
      )
      # Ensure the structure field is present before filling
      expect(page).to have_field("Structure", wait: 5)
      fill_in "Structure", with: structure_json

      click_button "Create Service template"

      expect(page).to have_content("Service template was successfully created.")
      expect(page).to have_current_path(admin_service_template_path(ServiceTemplate.last), wait: 10)
      expect(page).to have_content("Landscaping Basic")
      expect(page).to have_content("Landscaping")
      expect(page).to have_content("Full website")
    end
  end

  context "Editing a template", js: true do
    let!(:service_template) do
      st = create(:service_template, name: "Old Name", industry: :general)
      st # Return the created object
    end

    it "allows admin to update template details and pages" do
      edit_path = edit_admin_service_template_path(service_template)
      visit edit_path
      # Wait for the edit form page to load and the Name field to be present
      expect(page).to have_field("Name", with: "Old Name", wait: 10)

      fill_in "Name", with: "Updated Landscaping Pro"
      fill_in "Description", with: "Updated pro template"
      select "Pool service", from: "Industry"
      uncheck "Active"

      updated_structure_json = JSON.pretty_generate(
        pages: [
          { title: "Home Updated", slug: "home", page_type: "home" },
          { title: "Contact", slug: "contact", page_type: "contact" }
        ]
      )
      # Ensure the structure field is present before filling
      expect(page).to have_field("Structure", wait: 5)
      fill_in "Structure", with: updated_structure_json

      click_button "Update Service template"

      expect(page).to have_current_path(admin_service_template_path(service_template), wait: 10)
      expect(page).to have_css('.flash_notice', text: 'Service template was successfully updated.', wait: 10)
      expect(page).to have_content("Updated Landscaping Pro")
      expect(page).to have_content("Pool service")
      expect(page).to have_content("No") # Assuming 'Active' unchecked results in 'No'
    end
  end

  context "Deleting a template" do
    let!(:service_template_to_delete) { create(:service_template) }

    it "allows admin to delete a template" do
      visit admin_service_templates_path

      within "#service_template_#{service_template_to_delete.id}" do
        find_link("Delete").click
      end

      expect(page).not_to have_content(service_template_to_delete.name)
    end
  end
end 