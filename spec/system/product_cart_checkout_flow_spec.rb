require 'rails_helper'

RSpec.describe 'Product Cart and Checkout Flow', type: :system do
  let!(:business) { create(:business, host_type: 'subdomain') }
  let!(:product) { create(:product, name: 'Test Product', active: true, business: business) }
  let!(:variant) { create(:product_variant, product: product, name: 'Default', stock_quantity: 2, price_modifier: 0.0) }
  let!(:shipping_method) { create(:shipping_method, name: 'Standard', cost: 5.0, business: business) }
  let!(:tax_rate) { create(:tax_rate, name: 'Sales Tax', rate: 0.1, business: business) }
  let!(:user) { 
    user = create(:user, email: 'test-customer@example.com', password: 'password123', password_confirmation: 'password123')
    user.confirm # Confirm the user's email so they can sign in
    user
  }
  let!(:tenant_customer) { create(:tenant_customer, business: business, email: user.email) }

  before do
    driven_by(:rack_test)
    business.save! unless business.persisted?
    ActsAsTenant.current_tenant = business
    set_tenant(business)
    
    # Mock Stripe checkout session creation for all tests
    allow(StripeService).to receive(:create_payment_checkout_session).and_return({
      session: double('Stripe::Checkout::Session', url: 'https://checkout.stripe.com/pay/cs_test_123')
    })
  end

  it 'allows a user to browse, add to cart, checkout, and redirects to Stripe' do
    with_subdomain(business.subdomain) do
      # First sign in the user
      visit new_user_session_path
      fill_in 'Email', with: user.email
      fill_in 'Password', with: 'password123'
      click_button 'Sign In'
      
      # Browse products
      visit products_path
      expect(page).to have_content('Test Product')
      click_link 'Test Product'
      expect(page).to have_content('Default')
      
      # Add to cart using direct HTTP request
      page.driver.post line_items_path, { product_variant_id: variant.id, quantity: 2 }
      
      # Visit cart to verify item was added
      visit cart_path
      expect(page).to have_content('Test Product')
      
      # Proceed to checkout
      click_link 'Proceed to Checkout'
      
      # Fill out checkout form
      select_shipping_method 'Standard'
      click_button 'Complete Order'
      
      # Should redirect to Stripe (mocked)
      expect(current_url).to eq('https://checkout.stripe.com/pay/cs_test_123')
      
      # Verify order was created
      order = Order.last
      expect(order).to be_present
      expect(order.tenant_customer).to eq(tenant_customer)
      expect(order.invoice).to be_present
    end
  end

  it 'shows an error if user tries to order more than available stock' do
    with_subdomain(business.subdomain) do
      # First sign in the user
      visit new_user_session_path
      fill_in 'Email', with: user.email
      fill_in 'Password', with: 'password123'
      click_button 'Sign In'
      
      # Browse products
      visit products_path
      click_link 'Test Product'
      
      # Add more than available stock to cart
      page.driver.post line_items_path, { product_variant_id: variant.id, quantity: 3 }
      
      visit cart_path
      click_link 'Proceed to Checkout'
      
      # Fill out checkout form
      select_shipping_method 'Standard'
      click_button 'Complete Order'
      
      # Expect the line item stock validation message
      expect(page).to have_content('Quantity for Default is not sufficient')
    end
  end

  it 'allows a guest to browse, add to cart, checkout, and redirects to Stripe' do
    with_subdomain(business.subdomain) do
      # Browse products as guest
      visit products_path
      click_link 'Test Product'
      
      # Add to cart using direct HTTP request
      page.driver.post line_items_path, { product_variant_id: variant.id, quantity: 2 }
      
      visit cart_path
      click_link 'Proceed to Checkout'
      
      # Fill in guest information
      fill_in 'First Name', with: 'Guest'
      fill_in 'Last Name', with: 'User'
      fill_in 'Email', with: 'guest@example.com'
      fill_in 'Phone', with: '555-5555'
      
      # Fill out checkout form
      select_shipping_method 'Standard'
      click_button 'Complete Order'
      
      # Should redirect to Stripe (mocked)
      expect(current_url).to eq('https://checkout.stripe.com/pay/cs_test_123')
      
      # Verify order was created
      order = Order.last
      expect(order).to be_present
      expect(order.tenant_customer.email).to eq('guest@example.com')
    end
  end

  it 'allows a guest to checkout and create an account' do
    with_subdomain(business.subdomain) do
      # Browse products as guest
      visit products_path
      click_link 'Test Product'
      
      # Add to cart using direct HTTP request
      page.driver.post line_items_path, { product_variant_id: variant.id, quantity: 1 }
      
      visit cart_path
      click_link 'Proceed to Checkout'
      
      # Fill in guest information with account creation
      fill_in 'First Name', with: 'John'
      fill_in 'Last Name', with: 'Doe'
      fill_in 'Email', with: 'john.doe@example.com'
      fill_in 'Phone', with: '123-4567'
      check 'Create an account with these details?'
      fill_in 'Password', with: 'securepass'
      fill_in 'Confirm Password', with: 'securepass'
      
      # Fill out checkout form
      select_shipping_method 'Standard'
      click_button 'Complete Order'
      
      # With email confirmation enabled, user creation redirects to sign-in
      # because the new user needs to confirm their email before signing in
      expect(current_path).to eq('/users/sign_in')
      expect(page).to have_content('You have to confirm your email address before continuing')
      
      # Verify user account was created but not confirmed
      user = User.find_by(email: 'john.doe@example.com')
      expect(user).to be_present
      expect(user.confirmed?).to be false
      
      # Confirm the user and sign in to complete the order process
      user.confirm
      fill_in 'Email', with: 'john.doe@example.com'
      fill_in 'Password', with: 'securepass'
      click_button 'Sign In'
      
      # After sign-in, client users are redirected to dashboard
      expect(current_path).to eq('/dashboard')
      expect(page).to have_content('Signed in successfully')
    end
  end
end 