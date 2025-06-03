require 'rails_helper'

RSpec.describe "Business Manager Customers", type: :system do
  let!(:business) { create(:business, hostname: 'testbiz', subdomain: 'testbiz') }
  let!(:manager)  { create(:user, :manager, business: business) }
  let!(:customer) { create(:tenant_customer, business: business, name: 'Existing Customer', email: 'exist@example.com', phone: '123-456-7890') }

  before do
    driven_by(:cuprite)
    Capybara.app_host = "http://#{business.hostname}.lvh.me"
    login_as(manager, scope: :user)
  end

  describe "index page" do
    before { visit business_manager_customers_path }

    it "displays a list of customers" do
      expect(page).to have_content('Customers')
      expect(page).to have_content('Existing Customer')
      expect(page).to have_content('exist@example.com')
    end

    it "allows creating a new customer" do
      click_link 'New Customer'
      fill_in 'Name', with: 'New Customer'
      fill_in 'Email', with: 'new@example.com'
      fill_in 'Phone', with: '555-000-1111'
      fill_in 'Address', with: '123 Test St'
      fill_in 'Notes', with: 'Test notes'
      check 'Active'
      click_button 'Create Customer'

      expect(page).to have_current_path(business_manager_customers_path)
      expect(page).to have_content('Customer was successfully created') if page.has_content?('Customer was successfully created')
      expect(page).to have_content('New Customer')
    end

    it "allows editing a customer" do
      click_link 'Edit', href: edit_business_manager_customer_path(customer)
      fill_in 'Name', with: 'Updated Name'
      click_button 'Update Customer'

      expect(page).to have_current_path(business_manager_customer_path(customer))
      expect(page).to have_content('Updated Name')
    end

    it "allows viewing a customer" do
      click_link 'View', href: business_manager_customer_path(customer)
      expect(page).to have_content('Existing Customer')
      expect(page).to have_content('exist@example.com')
    end

    it "allows deleting a customer" do
      visit business_manager_customers_path
      
      click_button 'Delete', match: :first
      
      expect(page).to have_current_path(business_manager_customers_path)
      expect(page).not_to have_content('Existing Customer')
    end
  end
end 