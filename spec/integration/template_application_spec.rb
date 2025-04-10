require 'rails_helper'

RSpec.describe "Template Application", type: :integration do
  let(:admin_user) { create(:admin_user) }
  let(:business) { create(:business) }
  let(:service_template) { create(:service_template) }

  before do
    # Simulate the process of applying a template
    service_template.update!(
      structure: {
        pages: [
          { title: "Home", slug: "home", page_type: "home", content: "Welcome!" },
          { title: "About", slug: "about", page_type: "about", content: "About us" }
        ],
        settings: { 
          theme: "default", 
          colors: { primary: "#336699" } 
        }
      }
    )
  end

  # describe '#apply_to_business' do
  #   # This tests the placeholder implementation of apply_to_business
  #   # which currently just associates the template with the business
  #   it "associates the template with the business" do
  #     expect {
  #       service_template.apply_to_business(business)
  #     }.to change { business.reload.service_template_id }.from(nil).to(service_template.id)
  #   end
  # end

  # # These tests outline the expected behavior once the full implementation is complete
  # describe 'template application implementation' do
  #   it "creates pages for the business based on template structure" do
  #     expect {
  #       service_template.apply_to_business(business)
  #     }.to change { business.pages.count }.from(0).to(2)
      
  #     # Verify the pages were created correctly
  #     home_page = business.pages.find_by(slug: "home")
  #     expect(home_page).to be_present
  #     expect(home_page.title).to eq("Home")
  #     expect(home_page.content).to eq("Welcome!")
      
  #     about_page = business.pages.find_by(slug: "about")
  #     expect(about_page).to be_present
  #     expect(about_page.title).to eq("About")
  #     expect(about_page.content).to eq("About us")
  #   end

  #   it "applies template settings to the business" do
  #     service_template.apply_to_business(business)
  #     business.reload
      
  #     expect(business.theme).to eq("default")
  #     expect(business.settings["colors"]["primary"]).to eq("#336699")
  #   end
  # end
end 