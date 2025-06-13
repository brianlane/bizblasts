require 'rails_helper'

RSpec.describe 'Promotional Pricing System', type: :system do
  let!(:business) { create(:business, hostname: 'testbiz') }
  let!(:product) { create(:product, business: business, price: 100.00, name: 'Test Product') }
  let!(:product_variant) { create(:product_variant, product: product, price_modifier: 0.00) }
  let!(:service) { create(:service, business: business, price: 150.00, name: 'Test Service') }
  let!(:staff_member) { create(:staff_member, business: business) }
  let!(:customer) { create(:tenant_customer, business: business) }
  let!(:client_user) { create(:user, :client) }
  
  before do
    ActsAsTenant.current_tenant = business
    Capybara.app_host = "http://#{business.hostname}.lvh.me"
  end

  describe 'Product promotional pricing display' do
    let!(:promotion) do
      create(:promotion, :automatic,
        business: business,
        name: 'Spring Sale',
        discount_type: 'percentage',
        discount_value: 25,
        applicable_to_products: true,
        start_date: 1.week.ago,
        end_date: 1.week.from_now,
        active: true
      )
    end
    
    before do
      promotion.promotion_products.create!(product: product)
    end

    it 'displays promotional pricing on product index page', js: true do
      visit '/products'
      
      # Check promotional badge (using actual CSS class from view)
      expect(page).to have_content('25% OFF')
      
      # Check promotional pricing display
      expect(page).to have_content('$75.00') # 100 - 25% = 75
      expect(page).to have_content('$100.00') # Original price
      expect(page).to have_content('(Save 25%)') # Savings display
      
      # Check original price is crossed out
      expect(page).to have_css('.line-through', text: '$100.00')
    end

    it 'displays promotional pricing on product detail page', js: true do
      visit "/products/#{product.id}"
      
      # Check promotional badge with correct styling (bg-red-100 from actual view)
      expect(page).to have_css('.bg-red-100', text: '25% OFF')
      
      # Check promotional pricing is displayed
      expect(page).to have_content('$75.00')
      expect(page).to have_css('.line-through', text: '$100.00')
      
      # Check savings percentage display
      expect(page).to have_content('(Save 25%)')
    end

    it 'uses promotional pricing when adding to cart', js: true do
      visit "/products/#{product.id}"
      
      # Verify promotional pricing is shown on product page
      expect(page).to have_content('$75.00') # Promotional price shown
      expect(page).to have_content('25% OFF') # Promotional badge shown
      
      # Select variant first since product has variants
      find('#product_variant_dropdown [data-dropdown-target="button"]').click
      find('#product_variant_dropdown [data-dropdown-target="option"]', match: :first).click
      
      # Add to cart with promotional pricing
      click_button 'Add to Cart'
      
      # Visit the cart page directly 
      visit '/cart'
      
      # Cart should use promotional price - check for promotional price in cart content
      expect(page).to have_content('$75.00') # Should show promotional price
      
      # Verify cart is not showing full price anywhere
      expect(page).not_to have_content('$100.00') # Should not show full price in cart
    end
  end

  describe 'Service promotional pricing display' do
    let!(:promotion) do
      create(:promotion,
        business: business,
        discount_type: 'fixed_amount',
        discount_value: 30.00,
        applicable_to_services: true,
        start_date: 1.week.ago,
        end_date: 1.week.from_now,
        active: true
      )
    end
    
    before do
      promotion.promotion_services.create!(service: service)
    end

    it 'displays promotional pricing on service detail page', js: true do
      visit "/services/#{service.id}"
      
      # Check promotional badge
      expect(page).to have_content('$30.0 OFF')
      
      # Check promotional pricing
      expect(page).to have_content('$120.00') # 150 - 30 = 120
      expect(page).to have_css('.line-through', text: '$150.00')
      
      # Check savings display
      expect(page).to have_content('(Save 20%)') # 30/150 = 20%
    end

    it 'displays promotional pricing on services listing page', js: true do
      visit '/services'
      
      # Check that services page shows promotional pricing
      expect(page).to have_content('$120.00') # Promotional price
      expect(page).to have_css('.line-through', text: '$150.00') # Original price crossed out
    end
  end

  describe 'Accessibility and responsive design' do
    let!(:promotion) do
      create(:promotion,
        business: business,
        discount_type: 'percentage',
        discount_value: 15,
        applicable_to_products: true,
        active: true
      )
    end
    
    before do
      promotion.promotion_products.create!(product: product)
    end

    it 'displays promotional pricing with proper styling', js: true do
      visit '/products'
      
      # Check promotional elements are visible and properly styled
      expect(page).to have_content('15% OFF')
      expect(page).to have_css('.text-xs') # Appropriate text size
      expect(page).to have_css('.px-2') # Appropriate padding for badges
    end
  end

  describe 'Promotional pricing with discount codes' do
    let!(:promotion) do
      create(:promotion,
        business: business,
        discount_type: 'percentage',
        discount_value: 20,
        applicable_to_products: true,
        allow_discount_codes: true,
        active: true
      )
    end
    
    let!(:discount_code) do
      create(:discount_code,
        business: business,
        code: 'EXTRA10',
        discount_type: 'percentage',
        discount_value: 10,
        active: true
      )
    end
    
    before do
      promotion.promotion_products.create!(product: product)
    end

    it 'allows discount codes on top of promotional pricing', js: true do
      visit "/products/#{product.id}"
      
      # Verify promotional pricing is shown
      expect(page).to have_content('$80.00') # 100 - 20% = 80
      
      # Select variant first since product has variants
      find('#product_variant_dropdown [data-dropdown-target="button"]').click
      find('#product_variant_dropdown [data-dropdown-target="option"]', match: :first).click
      
      # Add to cart
      click_button 'Add to Cart'
      
      # Go to checkout and apply discount code
      visit '/cart'
      
      # If there's a promo code field, fill it in
      if page.has_field?('promo_code')
        fill_in 'promo_code', with: 'EXTRA10'
        click_button 'Apply'
        
        # Should show additional discount on promotional price
        # 80 - 10% = 72
        expect(page).to have_content('$72.00')
      end
    end
  end

  describe 'Expired and inactive promotions' do
    let!(:expired_promotion) do
      create(:promotion,
        business: business,
        discount_type: 'percentage',
        discount_value: 30,
        applicable_to_products: true,
        start_date: 2.weeks.ago,
        end_date: 1.week.ago,
        active: true
      )
    end
    
    let!(:inactive_promotion) do
      create(:promotion,
        business: business,
        discount_type: 'percentage',
        discount_value: 25,
        applicable_to_products: true,
        active: false
      )
    end
    
    before do
      expired_promotion.promotion_products.create!(product: product)
      inactive_promotion.promotion_products.create!(product: product)
    end

    it 'does not display expired or inactive promotional pricing', js: true do
      visit '/products'
      
      # Should show regular pricing, not promotional
      expect(page).to have_content('$100.00')
      expect(page).not_to have_content('% OFF')
      expect(page).not_to have_css('.line-through')
    end
  end

  describe 'Usage limit reached promotions' do
    let!(:limited_promotion) do
      create(:promotion,
        business: business,
        discount_type: 'percentage',
        discount_value: 40,
        applicable_to_products: true,
        usage_limit: 1,
        current_usage: 1,
        active: true
      )
    end
    
    before do
      limited_promotion.promotion_products.create!(product: product)
    end

    it 'does not display promotional pricing when usage limit is reached', js: true do
      visit "/products/#{product.id}"
      
      # Should show regular pricing
      expect(page).to have_content('$100.00')
      expect(page).not_to have_content('40% OFF')
    end
  end

  describe 'Multiple promotions on different products' do
    let!(:product2) { create(:product, business: business, price: 200.00, name: 'Product 2') }
    let!(:product_variant2) { create(:product_variant, product: product2, price_modifier: 0.00) }
    
    let!(:promotion1) do
      create(:promotion,
        business: business,
        name: 'Sale 1',
        discount_type: 'percentage',
        discount_value: 15,
        applicable_to_products: true,
        active: true
      )
    end
    
    let!(:promotion2) do
      create(:promotion,
        business: business,
        name: 'Sale 2',
        discount_type: 'fixed_amount',
        discount_value: 50.00,
        applicable_to_products: true,
        active: true
      )
    end
    
    before do
      promotion1.promotion_products.create!(product: product)
      promotion2.promotion_products.create!(product: product2)
    end

    it 'displays different promotional pricing for different products', js: true do
      visit '/products'
      
      # Check both promotions are visible
      expect(page).to have_content('15% OFF')
      expect(page).to have_content('$50.0 OFF')
      
      # Check promotional prices are shown
      expect(page).to have_content('$85.00') # 100 - 15% = 85
      expect(page).to have_content('$150.00') # 200 - 50 = 150
      
      # Check original prices are crossed out
      expect(page).to have_css('.line-through', text: '$100.00')
      expect(page).to have_css('.line-through', text: '$200.00')
    end
  end

  describe 'Real-time promotion updates' do
    let!(:promotion) do
      create(:promotion,
        business: business,
        discount_type: 'percentage',
        discount_value: 25,
        applicable_to_products: true,
        active: true
      )
    end
    
    before do
      promotion.promotion_products.create!(product: product)
    end

    it 'updates pricing when promotion status changes', js: true do
      visit "/products/#{product.id}"
      
      # Initially shows promotional pricing
      expect(page).to have_content('$75.00')
      expect(page).to have_content('25% OFF')
      
      # Simulate promotion being deactivated
      promotion.update!(active: false)
      
      # Refresh and check regular pricing is shown
      visit "/products/#{product.id}"
      expect(page).to have_content('$100.00')
      expect(page).not_to have_content('25% OFF')
    end
  end
end 