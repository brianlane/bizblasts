require 'rails_helper'

RSpec.describe "Admin Template Management", type: :system, admin: true do
  let!(:admin_user) { create(:admin_user) }

  before do
    login_as(admin_user, scope: :admin_user)
  end

  context "Creating a new template", js: true do
    it "allows admin to create a template with pages" do
      visit new_admin_service_template_path
      # Wait for the form page to load - looking for specific ActiveAdmin field ID
      expect(page).to have_field("service_template[name]", wait: 10)

      fill_in "service_template[name]", with: "Landscaping Basic"
      fill_in "service_template[description]", with: "Basic template for landscaping businesses"
      select "Landscaping", from: "service_template[industry]"
      select "Full website", from: "service_template[template_type]"
      check "service_template[active]"

      structure_json = JSON.pretty_generate(
        pages: [
          { title: "Home", slug: "home", page_type: "home" },
          { title: "Services", slug: "services", page_type: "services" }
        ]
      )
      # Ensure the structure field is present before filling
      expect(page).to have_field("service_template[structure]", wait: 5)
      fill_in "service_template[structure]", with: structure_json

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
      expect(page).to have_field("service_template[name]", wait: 10)
      
      # Verify the current value is loaded 
      expect(find_field("service_template[name]").value).to eq("Old Name")

      fill_in "service_template[name]", with: "Updated Landscaping Pro"
      fill_in "service_template[description]", with: "Updated pro template"
      select "Pool service", from: "service_template[industry]"
      uncheck "service_template[active]"

      updated_structure_json = JSON.pretty_generate(
        pages: [
          { title: "Home Updated", slug: "home", page_type: "home" },
          { title: "Contact", slug: "contact", page_type: "contact" }
        ]
      )
      # Ensure the structure field is present before filling
      expect(page).to have_field("service_template[structure]", wait: 5)
      fill_in "service_template[structure]", with: updated_structure_json

      click_button "Update Service template"

      expect(page).to have_content("Updated Landscaping Pro")
      expect(page).to have_content("Pool service")
      # Verify active status change
      expect(page).to have_content("Active No")
    end
  end

  context "Deleting a template" do
    let!(:service_template_to_delete) { create(:service_template) }

    it "allows admin to delete a template" do
      visit admin_service_templates_path

      # Get the template name for verification later
      template_name = service_template_to_delete.name
      
      # Find the delete link in the actions column - more robust approach
      within("tr", text: template_name) do
        # Find the delete link within the actions column
        find("a[data-method='delete']").click
      end

      # Verify that the template was deleted
      expect(page).not_to have_content(template_name)
    end
  end
end 