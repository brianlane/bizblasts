require 'rails_helper'

RSpec.describe "Admin Dashboard", type: :system do
  let!(:admin_user) { create(:admin_user) }
  let!(:company) { create(:company, name: "Test Company") }
  let!(:user) { create(:user, company: company) }
  let!(:service_template) { create(:service_template, name: "Website Template") }
  let!(:client_website) { create(:client_website, name: "Test Website", company: company, service_template: service_template) }

  before do
    driven_by(:selenium_headless)
    sign_in admin_user
    visit admin_dashboard_path
  end

  it "shows the dashboard with system overview" do
    expect(page).to have_content("Dashboard")
    expect(page).to have_content("System Overview")
    expect(page).to have_content("Total Companies")
    expect(page).to have_content("1") # Count of companies
  end

  it "shows recent activity section" do
    expect(page).to have_content("Recent Activity")
    expect(page).to have_content("Test Company")
    expect(page).to have_content("Test Website")
  end

  it "has working navigation to Companies section" do
    click_link "Companies"
    expect(page).to have_current_path(admin_companies_path)
    expect(page).to have_content("Test Company")
  end

  it "has working navigation to Client Websites section" do
    click_link "Client Websites"
    expect(page).to have_current_path(admin_client_websites_path)
    expect(page).to have_content("Test Website")
  end

  it "allows admin to visit company details" do
    click_link "Companies"
    click_link "Test Company"
    expect(page).to have_current_path(admin_company_path(company))
    expect(page).to have_content("Company Details")
    expect(page).to have_content("Users")
    expect(page).to have_content("Client Websites")
  end

  it "allows admin to visit client website details" do
    click_link "Client Websites"
    click_link "Test Website"
    expect(page).to have_current_path(admin_client_website_path(client_website))
    expect(page).to have_content("Client Website Details")
  end
end 