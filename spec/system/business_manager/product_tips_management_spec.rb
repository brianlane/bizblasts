require 'rails_helper'

RSpec.describe "Product Tips Management", type: :system do
  include_context 'setup business context'

  before do
    driven_by(:rack_test)
    login_as(manager, scope: :user)
    switch_to_subdomain(business.subdomain)
    Rails.application.reload_routes!
  end

  context "when creating a new product" do
    scenario "manager can enable tips for a new product" do
      visit business_manager_products_path

      click_link "New Product"

      fill_in "Name", with: "Premium Coffee"
      fill_in "Description", with: "High quality coffee beans"
      fill_in "Base Price ($)", with: "29.99"
      check "Enable tips"
      check "Active"

      click_button "Create Product"

      expect(page).to have_content("Product was successfully created")
      
      product = Product.last
      expect(product.tips_enabled).to be true
    end

    scenario "manager can create a product without tips enabled" do
      visit business_manager_products_path

      click_link "New Product"

      fill_in "Name", with: "Basic Coffee"
      fill_in "Description", with: "Standard coffee beans"
      fill_in "Base Price ($)", with: "19.99"
      # Don't check "Enable tips"
      check "Active"

      click_button "Create Product"

      expect(page).to have_content("Product was successfully created")
      
      product = Product.last
      expect(product.tips_enabled).to be false
    end
  end

  context "when editing an existing product" do
    let!(:product) { create(:product, business: business, name: "Test Product", tips_enabled: false) }

    scenario "manager can enable tips for an existing product" do
      visit edit_business_manager_product_path(product)

      check "Enable tips"
      click_button "Update Product"

      expect(page).to have_content("Product was successfully updated")
      
      product.reload
      expect(product.tips_enabled).to be true
    end

    scenario "manager can disable tips for an existing product" do
      product.update!(tips_enabled: true)
      
      visit edit_business_manager_product_path(product)

      uncheck "Enable tips"
      click_button "Update Product"

      expect(page).to have_content("Product was successfully updated")
      
      product.reload
      expect(product.tips_enabled).to be false
    end
  end

  context "form validation and UI" do
    scenario "tips checkbox is visible and properly labeled" do
      visit new_business_manager_product_path

      expect(page).to have_field("Enable tips", type: "checkbox")
      expect(page).to have_content("Enable tips")
    end

    scenario "tips checkbox state is preserved when editing" do
      product = create(:product, business: business, tips_enabled: true)
      
      visit edit_business_manager_product_path(product)

      expect(page).to have_checked_field("Enable tips")
    end
  end
end 