require 'rails_helper'

RSpec.describe 'Variant Removal', type: :system do
  include_context 'setup business context'
  
  before do
    driven_by(:cuprite)
    login_as(manager, scope: :user)
    switch_to_subdomain(business.subdomain)
    Rails.application.reload_routes!
  end
  
  describe 'removing variants from products' do
    let(:product) { create(:product, business: business, name: 'Test Product', price: 25.00) }
    
    before do
      # Create some variants to test removal
      create(:product_variant, product: product, name: 'Small', price_modifier: -5)
      create(:product_variant, product: product, name: 'Large', price_modifier: 5)
      create(:product_variant, product: product, name: 'XL', price_modifier: 10)
    end
    
    it 'removes variants and persists the changes' do
      initial_variant_count = product.product_variants.count
      expect(initial_variant_count).to eq(4) # Default + 3 user-created
      
      visit edit_business_manager_product_path(product)
      
      # Wait for the variant fields to load
      expect(page).to have_css('.variant-field', count: 4, wait: 10)
      
      # Verify all variants are showing by checking for fields containing their names
      expect(page).to have_field(type: 'text', with: 'Default')
      expect(page).to have_field(type: 'text', with: 'Small')
      expect(page).to have_field(type: 'text', with: 'Large')
      expect(page).to have_field(type: 'text', with: 'XL')
      
      # Remove the "Large" variant by clicking its Remove button
      within(:xpath, "//input[@value='Large']/ancestor::div[contains(@class, 'variant-field')]") do
        click_button 'Remove Variant'
      end
      
      # The variant should be hidden but still in DOM (marked for destruction)
      large_variant_field = page.find(:xpath, "//input[@value='Large']/ancestor::div[contains(@class, 'variant-field')]", visible: false)
      expect(large_variant_field).not_to be_visible
      
      # Submit the form
      click_button 'Update Product'
      
      # Should redirect to product show page
      expect(page).to have_content('Product was successfully updated')
      
      # Verify the variant was actually removed from the database
      product.reload
      expect(product.product_variants.count).to eq(3) # Default + Small + XL
      expect(product.product_variants.pluck(:name)).to contain_exactly('Default', 'Small', 'XL')
      expect(product.product_variants.pluck(:name)).not_to include('Large')
    end
    
    it 'can remove multiple variants in one update' do
      visit edit_business_manager_product_path(product)
      
      # Remove both "Small" and "XL" variants
      within(:xpath, "//input[@value='Small']/ancestor::div[contains(@class, 'variant-field')]") do
        click_button 'Remove Variant'
      end
      
      within(:xpath, "//input[@value='XL']/ancestor::div[contains(@class, 'variant-field')]") do
        click_button 'Remove Variant'
      end
      
      # Submit the form
      click_button 'Update Product'
      
      expect(page).to have_content('Product was successfully updated')
      
      # Verify both variants were removed
      product.reload
      expect(product.product_variants.count).to eq(2) # Default + Large
      expect(product.product_variants.pluck(:name)).to contain_exactly('Default', 'Large')
    end
    
    it 'shows remove buttons when there are multiple variants' do
      visit edit_business_manager_product_path(product)
      
      # Wait for variant fields to load
      expect(page).to have_css('.variant-field', count: 4, wait: 10)
      
      # Should see multiple variants with visible remove buttons
      expect(page).to have_field(type: 'text', with: 'Default')
      expect(page).to have_field(type: 'text', with: 'Small')
      expect(page).to have_field(type: 'text', with: 'Large')
      
      # All variants should have visible remove buttons
      expect(page).to have_button('Remove Variant', count: 4) # Default + 3 user-created
    end
  end
end 