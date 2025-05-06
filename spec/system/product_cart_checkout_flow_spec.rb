require 'rails_helper'

RSpec.describe 'Product Cart and Checkout Flow', type: :feature do
  let!(:business) { create(:business, subdomain: 'testtenant', hostname: 'testtenant', host_type: 'subdomain') }
  let!(:product) { create(:product, name: 'Test Product', active: true, business: business) }
  let!(:variant) { create(:product_variant, product: product, name: 'Default', stock_quantity: 2) }
  let!(:shipping_method) { create(:shipping_method, name: 'Standard', cost: 5.0, business: business) }
  let!(:tax_rate) { create(:tax_rate, name: 'Sales Tax', rate: 0.1, business: business) }
  let!(:tenant_customer) { create(:tenant_customer, business: business) }

  before do
    business.save! unless business.persisted?
    ActsAsTenant.current_tenant = business
    set_tenant(business)
  end

  it 'allows a user to browse, add to cart, checkout, and confirm order' do
    puts "DEBUG: All Products in DB:"
    Product.all.each do |p|
      puts "  id=#{p.id}, name=#{p.name}, business_id=#{p.business_id}, active=#{p.active}, product_type=#{p.product_type}"
    end
    with_subdomain('testtenant') do
      visit products_path
      expect(page).to have_content('Test Product')
      click_link 'Test Product'
      expect(page).to have_content('Default')
      select 'Default', from: 'variant'
      fill_in 'quantity', with: 2
      click_button 'Add to Cart'
      visit cart_path
      expect(page).to have_content('Test Product')
      expect(page).to have_content('2')
      click_link 'Checkout'
      fill_in 'Customer', with: tenant_customer.id
      select 'Standard', from: 'Shipping Method'
      select 'Sales Tax', from: 'Tax Rate'
      click_button 'Place Order'
      expect(page).to have_content('Order Confirmation')
      expect(page).to have_content('Test Product')
      expect(page).to have_content('2')
      expect(page).to have_content('Standard')
      expect(page).to have_content('Sales Tax')
    end
  end

  it 'shows an error if user tries to order more than available stock' do
    with_subdomain('testtenant') do
      visit products_path
      click_link 'Test Product'
      select 'Default', from: 'variant'
      fill_in 'quantity', with: 3
      click_button 'Add to Cart'
      visit cart_path
      click_link 'Checkout'
      fill_in 'Customer', with: tenant_customer.id
      select 'Standard', from: 'Shipping Method'
      select 'Sales Tax', from: 'Tax Rate'
      click_button 'Place Order'
      expect(page).to have_content('Insufficient stock')
    end
  end
end 