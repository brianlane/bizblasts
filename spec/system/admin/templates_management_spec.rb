require 'rails_helper'

RSpec.describe "Admin Template Management", type: :system, admin: true do
  let!(:admin_user) { create(:admin_user) }

  before do
    driven_by(:cuprite)
    login_as(admin_user, scope: :admin_user)
  end

  context "Creating a new template", js: true do
    it "allows admin to create a template with pages" do
      visit new_admin_service_template_path
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
      create(:service_template, 
        name: "Template 1",
        description: "A website template for service businesses",
        industry: :landscaping,
        active: true,
        structure: {
          pages: [
            { slug: "home", title: "Home", content: "Welcome home!", page_type: "home" },
            { slug: "about", title: "About", content: "About us...", page_type: "about" },
            { slug: "contact", title: "Contact", content: "Contact us!", page_type: "contact" }
          ],
          theme: "default",
          settings: { show_header: true }
        }.to_json
      )
    end

    it "allows admin to update template details and pages" do
      visit edit_admin_service_template_path(service_template)

      expect(page).to have_field("service_template[name]", wait: 10)
      expect(find_field("service_template[name]").value).to eq("Template 1")

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
      fill_in "service_template[structure]", with: updated_structure_json

      click_button "Update Service template"

      expect(page).to have_content("Service template was successfully updated.")
      expect(page).to have_content("Updated Landscaping Pro")
      expect(page).to have_content("Pool service")
      
      within('.attributes_table tr.row-active') do
        expect(page).to have_selector("td", text: "NO")
      end
    end
  end

  # context "Deleting a template" do
  #   let!(:template) { create(:service_template, name: "Template 1") }

  #   it "allows admin to delete a template", js: true do
  #     visit admin_service_templates_path
  #     expect(page).to have_content(template.name)
      
  #     # Configure Cuprite to auto-accept confirms
  #     page.driver.execute_script('window.confirm = function() { return true; }')
      
  #     within("tr", text: template.name) do
  #       click_link "Delete"
  #     end

  #     # Wait for the deletion to complete
  #     sleep 1
      
  #     expect(page).to have_content("Service template was successfully destroyed.")
  #     expect(page).not_to have_content(template.name)
  #   end
  # end
end