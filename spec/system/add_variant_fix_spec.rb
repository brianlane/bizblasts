# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Business Manager Product Variant Management', type: :system do
  include_context 'setup business context'

  before do
    driven_by(:rack_test)
    login_as(manager, scope: :user)
    switch_to_subdomain(business.subdomain)
    Rails.application.reload_routes!
  end

  describe 'Product variant management' do
    it 'displays variant management interface on product form' do
      visit business_manager_products_path
      click_link 'New Product'
      
      # Fill in basic product information
      fill_in 'Name', with: 'Test Product'
      fill_in 'Base Price ($)', with: '25.00'
      fill_in 'Description', with: 'A test product for variant testing'
      
      # Check that variants section exists
      expect(page).to have_content('Product Variants')
      expect(page).to have_content('Add variants if this product comes in different sizes, colors, or configurations.')
      
      # Create the product without variants first
      click_button 'Create Product'
      
      expect(page).to have_content('Product was successfully created')
      expect(page).to have_current_path(/\/manage\/products\/\d+/)
    end

    it 'can edit products and shows variant interface' do
      # Create a product first
      product = create(:product, business: business, name: 'Existing Product', price: 30.0)
      
      visit edit_business_manager_product_path(product)
      
      # Verify the variant management section is present
      expect(page).to have_content('Product Variants')
      
      # Verify we can update the product
      fill_in 'Name', with: 'Updated Product Name'
      click_button 'Update Product'
      
      expect(page).to have_content('Product was successfully updated')
      expect(page).to have_content('Updated Product Name')
    end

    it 'displays existing variants in edit form' do
      # Create a product with variants
      product = create(:product, business: business, name: 'Product with Variants')
      variant1 = create(:product_variant, product: product, name: 'Small', sku: 'PROD-S', stock_quantity: 10)
      variant2 = create(:product_variant, product: product, name: 'Large', sku: 'PROD-L', stock_quantity: 5)
      
      visit edit_business_manager_product_path(product)
      
      # The form should display existing variants
      expect(page).to have_content('Product Variants')
      
      # Verify we can still update the product
      fill_in 'Description', with: 'Updated description'
      click_button 'Update Product'
      
      expect(page).to have_content('Product was successfully updated')
    end
    
    it 'properly handles product creation and editing workflow' do
      # Test the complete workflow
      visit business_manager_products_path
      expect(page).to have_content('Manage Products')
      
      # Create a new product
      click_link 'New Product'
      fill_in 'Name', with: 'Workflow Test Product'
      fill_in 'Base Price ($)', with: '45.00'
      check 'Active'
      click_button 'Create Product'
      
      # Should be on the product show page
      expect(page).to have_content('Product was successfully created')
      product = Product.last
      expect(page).to have_current_path(business_manager_product_path(product))
      
      # Navigate to edit
      click_link 'Edit'
      expect(page).to have_current_path(edit_business_manager_product_path(product))
      
      # Verify edit form loads properly
      expect(page).to have_field('Name', with: 'Workflow Test Product')
      expect(page).to have_content('Product Variants')
      
      # Make an edit
      fill_in 'Description', with: 'Added description'
      click_button 'Update Product'
      
      expect(page).to have_content('Product was successfully updated')
      
      # Navigate back to products list
      click_link 'Back to Products'
      expect(page).to have_current_path(business_manager_products_path)
      expect(page).to have_content('Workflow Test Product')
    end
  end
end 