require 'rails_helper'

RSpec.describe 'Variant Label Customization', type: :system do
  include_context 'setup business context'
  
  before do
    driven_by(:rack_test)
    login_as(manager, scope: :user)
    switch_to_subdomain(business.subdomain)
    Rails.application.reload_routes!
  end
  
  describe 'Business manager can customize variant labels' do
    let(:product) { create(:product, business: business, name: 'Test Product', price: 25.00) }
    
    context 'when product has no user-created variants' do
      it 'hides variant customization options in product form' do
        visit edit_business_manager_product_path(product)
        
        expect(page).not_to have_content('Variant Display Settings')
        expect(page).not_to have_field('Variant Selection Label')
      end
    end
    
    context 'when product has multiple user-created variants' do
      before do
        create(:product_variant, product: product, name: 'Small', price_modifier: 0)
        create(:product_variant, product: product, name: 'Large', price_modifier: 5)
      end
      
      it 'shows variant customization options in product form' do
        visit edit_business_manager_product_path(product)
        
        expect(page).to have_content('Variant Display Settings')
        expect(page).to have_field('Variant Selection Label')
        expect(page).to have_content('Products with only one variant will automatically hide the dropdown')
      end
      
      it 'allows customizing variant label text' do
        visit edit_business_manager_product_path(product)
        
        fill_in 'Variant Selection Label', with: 'Choose a size'
        click_button 'Update Product'
        
        expect(page).to have_content('Product was successfully updated')
        expect(product.reload.variant_label_text).to eq('Choose a size')
      end
    end
    

  end
  
  describe 'Customer sees customized variant labels' do
    let(:product) { create(:product, business: business, name: 'Test Product', price: 25.00, variant_label_text: 'Pick a size') }
    
    before do
      # Create user-defined variants (not just default)
      create(:product_variant, product: product, name: 'Small', price_modifier: 0)
      create(:product_variant, product: product, name: 'Large', price_modifier: 5)
    end
    
    it 'shows custom variant label on product page' do
      visit "/products/#{product.id}"
      
      expect(page).to have_content('Pick a size:')
    end
  end
  
  describe 'Variant selector display logic' do
    context 'when product has only default variant' do
      let(:product) do 
        create(:product, 
               business: business, 
               name: 'Single Variant Product', 
               price: 25.00, 
               variant_label_text: 'Choose a size')
      end
      
      # Don't create additional variants - product will only have the default variant
      
      it 'automatically hides variant selector when only one variant exists' do
        visit "/products/#{product.id}"
        
        # Should not show the variant dropdown label
        expect(page).not_to have_content('Choose a size:')
        # But should still allow adding to cart
        expect(page).to have_button('Add to Cart')
      end
    end
    
    context 'when product has 2 or more variants' do
      let(:product) do 
        create(:product, 
               business: business, 
               name: 'Multi Variant Product', 
               price: 25.00, 
               variant_label_text: 'Choose a size')
      end
      
      before do
        # Create user-defined variant in addition to default
        create(:product_variant, product: product, name: 'Large', price_modifier: 5)
      end
      
      it 'shows variant selector when multiple variants exist' do
        visit "/products/#{product.id}"
        
        # Should show the variant dropdown label
        expect(page).to have_content('Choose a size:')
        # Should show variants in dropdown
        expect(page).to have_content('Default')
        expect(page).to have_content('Large')
        # Should still allow adding to cart
        expect(page).to have_button('Add to Cart')
      end
    end
  end
end 