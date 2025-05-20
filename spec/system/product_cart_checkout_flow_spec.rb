require 'rails_helper'

RSpec.describe 'Product Cart and Checkout Flow', type: :feature do
  let!(:business) { create(:business, subdomain: 'testtenant', hostname: 'testtenant', host_type: 'subdomain') }
  let!(:product) { create(:product, name: 'Test Product', active: true, business: business) }
  let!(:variant) { create(:product_variant, product: product, name: 'Default', stock_quantity: 2) }
  let!(:shipping_method) { create(:shipping_method, name: 'Standard', cost: 5.0, business: business) }
  let!(:tax_rate) { create(:tax_rate, name: 'Sales Tax', rate: 0.1, business: business) }
  let!(:user) { create(:user, email: 'test-customer@example.com', password: 'password123') }
  let!(:tenant_customer) { create(:tenant_customer, business: business, email: user.email) }

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
      # First sign in the user
      visit new_user_session_path
      fill_in 'Email', with: user.email
      fill_in 'Password', with: 'password123'
      click_button 'Log in'
      
      # Now proceed with the checkout flow
      visit products_path
      expect(page).to have_content('Test Product')
      click_link 'Test Product'
      expect(page).to have_content('Default')
      find('#variant').find("option[value='#{variant.id}']").select_option
      fill_in 'quantity', with: 2
      click_button 'Add to Cart'
      visit cart_path
      expect(page).to have_content('Test Product')
      expect(page).to have_field(class: 'quantity-input', with: '2', type: 'number')
      click_link 'Checkout'
      # No need to fill in customer ID since it's determined by the current_user
      select 'Standard', from: 'Shipping Method'
      click_button 'Place Order'
      
      # Check for order details instead of "Order Confirmation" heading
      expect(page).to have_content('Order Details:')
      expect(page).to have_content('Test Product')
      expect(page).to have_content('Default')
      expect(page).to have_content('2') # quantity
      expect(page).to have_content('Standard') # shipping method
      expect(page).to have_content('Sales Tax') # tax rate
    end
  end

  it 'shows an error if user tries to order more than available stock' do
    with_subdomain('testtenant') do
      # First sign in the user
      visit new_user_session_path
      fill_in 'Email', with: user.email
      fill_in 'Password', with: 'password123'
      click_button 'Log in'
      
      visit products_path
      click_link 'Test Product'
      find('#variant').find("option[value='#{variant.id}']").select_option
      fill_in 'quantity', with: 3
      click_button 'Add to Cart'
      visit cart_path
      click_link 'Checkout'
      # No need to fill in customer ID
      select 'Standard', from: 'Shipping Method'
      click_button 'Place Order'
      # Expect the line item stock validation message
      expect(page).to have_content('Quantity for Default is not sufficient')
    end
  end

  it 'allows a guest to browse, add to cart, checkout, and confirm order without an account' do
    with_subdomain('testtenant') do
      visit products_path
      click_link 'Test Product'
      find('#variant').find("option[value='#{variant.id}']").select_option
      fill_in 'quantity', with: 2
      click_button 'Add to Cart'
      visit cart_path
      click_link 'Checkout'
      fill_in 'First Name', with: 'Guest'
      fill_in 'Last Name', with: 'User'
      fill_in 'Email', with: 'guest@example.com'
      fill_in 'Phone', with: '555-5555'
      select 'Standard', from: 'Shipping Method'
      click_button 'Place Order'
      expect(page).to have_content('Order Details:')
      expect(page).to have_content('Test Product')
      expect(page).to have_content('Default')
      expect(page).to have_content('2')
    end
  end

  it 'allows a guest to checkout and create an account' do
    with_subdomain('testtenant') do
      visit products_path
      click_link 'Test Product'
      find('#variant').find("option[value='#{variant.id}']").select_option
      fill_in 'quantity', with: 1
      click_button 'Add to Cart'
      visit cart_path
      click_link 'Checkout'
      fill_in 'First Name', with: 'John'
      fill_in 'Last Name', with: 'Doe'
      fill_in 'Email', with: 'john.doe@example.com'
      fill_in 'Phone', with: '123-4567'
      check 'Create an account with these details?'
      fill_in 'Password', with: 'securepass'
      fill_in 'Confirm Password', with: 'securepass'
      select 'Standard', from: 'Shipping Method'
      click_button 'Place Order'
      expect(User.find_by(email: 'john.doe@example.com')).to be_present
      expect(page).to have_content('Order Details:')
    end
  end
end 