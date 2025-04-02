require 'rails_helper'

RSpec.describe "Admin Companies", type: :system do
  let!(:admin_user) { create(:admin_user) }
  let!(:company) { create(:company, name: "Test Company", subdomain: "testcompany") }
  
  before do
    driven_by(:selenium_headless)
    sign_in admin_user
    visit admin_companies_path
  end

  describe "index page" do
    it "lists all companies" do
      expect(page).to have_content("Companies")
      expect(page).to have_content("Test Company")
      expect(page).to have_content("testcompany")
    end

    it "has working links to view, edit, and delete" do
      within "tr", text: "Test Company" do
        expect(page).to have_link("View")
        expect(page).to have_link("Edit")
        expect(page).to have_link("Delete")
      end
    end
  end

  describe "show page" do
    it "displays company details" do
      within "tr", text: "Test Company" do
        click_link "View"
      end
      
      expect(page).to have_content("Company Details")
      expect(page).to have_content("Test Company")
      expect(page).to have_content("testcompany")
    end
  end

  describe "edit page" do
    it "allows updating a company" do
      within "tr", text: "Test Company" do
        click_link "Edit"
      end
      
      fill_in "Name", with: "Updated Company"
      click_button "Update Company"
      
      expect(page).to have_content("Company was successfully updated")
      expect(page).to have_content("Updated Company")
    end
  end

  describe "new page" do
    it "allows creating a new company" do
      click_link "New Company"
      
      fill_in "Name", with: "New Test Company"
      fill_in "Subdomain", with: "newtestcompany"
      click_button "Create Company"
      
      expect(page).to have_content("Company was successfully created")
      expect(page).to have_content("New Test Company")
      expect(page).to have_content("newtestcompany")
    end
  end

  describe "delete operation" do
    it "allows deleting a company", js: true do
      # Create a company that can be safely deleted
      deletable_company = create(:company, name: "Deletable Company")
      visit admin_companies_path
      
      within "tr", text: "Deletable Company" do
        accept_confirm do
          click_link "Delete"
        end
      end
      
      expect(page).to have_content("Company was successfully destroyed")
      expect(page).not_to have_content("Deletable Company")
    end
  end

  describe "batch actions" do
    before do
      create(:client_website, company: company, name: "Test Website", active: false)
    end
    
    it "allows activating websites for multiple companies" do
      visit admin_companies_path
      
      # Select the company
      find("input[type='checkbox'][value='#{company.id}']").click
      select "Activate websites", from: "batch_action"
      click_button "Batch Actions"
      
      expect(page).to have_content("Websites activated for selected companies")
    end
  end
end 