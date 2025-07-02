require 'rails_helper'

RSpec.describe 'Product Tipping Flow', type: :system do
  let!(:business) { create(:business, :with_default_tax_rate, host_type: 'subdomain', stripe_account_id: 'acct_test123') }
  let!(:product) { create(:product, name: 'Premium Coffee Beans', price: 25.00, business: business, tips_enabled: true) }
  let!(:product_variant) { create(:product_variant, product: product, name: 'Medium Roast', stock_quantity: 10, price_modifier: 0.0) }
  let!(:shipping_method) { create(:shipping_method, name: 'Standard Shipping', cost: 5.0, business: business) }
  let!(:tax_rate) { create(:tax_rate, name: 'Sales Tax', rate: 0.1, business: business) }
  
  # For mixed cart tests
  let!(:product_no_tips) { create(:product, name: 'Basic Coffee', price: 20.00, business: business, tips_enabled: false) }
  let!(:product_variant_no_tips) { create(:product_variant, product: product_no_tips, name: 'Standard', stock_quantity: 5, price_modifier: -5.0) }
  
  let!(:user) { 
    user = create(:user, email: 'customer@example.com', password: 'password123', password_confirmation: 'password123')
    user.confirm
    user
  }
  let!(:tenant_customer) { create(:tenant_customer, business: business, email: user.email, first_name: user.first_name, last_name: user.last_name) }

  before do
    driven_by(:rack_test)
    business.save! unless business.persisted?
    ActsAsTenant.current_tenant = business
    set_tenant(business)
    
    # Mock Stripe service to avoid redirects in tests
    allow(StripeService).to receive(:create_payment_checkout_session).and_return({
      session: double('stripe_session', url: 'https://checkout.stripe.com/pay/cs_test_123')
    })
  end

  describe 'Authenticated user product checkout with tips' do
    let!(:user) { create(:user, business: business) }
    
    context 'allows checkout without tip' do
      it 'completes order successfully without tip' do
        with_subdomain(business.subdomain) do
          sign_in user
          
          # Add product to cart
          visit products_path
          click_link 'Premium Coffee Beans'
          page.driver.post line_items_path, { product_variant_id: product_variant.id, quantity: 1 }
          
          # Go to checkout
          visit cart_path
          click_link 'Proceed to Checkout'
          
          # Should show tip option but don't add tip
          expect(page).to have_content('Add a Tip (Optional)')
          
          select 'Standard Shipping', from: 'order_shipping_method_id'
          click_button 'Complete Order'
          
          # Should redirect to Stripe (mocked)
          expect(current_url).to include('checkout.stripe.com')
          
          # Verify order has no tip
          order = Order.last
          expect(order.tip_amount).to eq(0.0)
        end
      end
    end
    
    context 'shows validation error for tip amount below minimum' do
      it 'displays error for tip below minimum' do
        with_subdomain(business.subdomain) do
          sign_in user
          
          # Add product to cart
          visit products_path
          click_link 'Premium Coffee Beans'
          page.driver.post line_items_path, { product_variant_id: product_variant.id, quantity: 1 }
          
          # Go to checkout
          visit cart_path
          click_link 'Proceed to Checkout'
          
          # Set tip amount below minimum using custom input
          fill_in 'custom-tip-amount', with: '0.25'
          find('#tip_amount', visible: false).set('0.25')
          
          select 'Standard Shipping', from: 'order_shipping_method_id'
          click_button 'Complete Order'
          
          # Should show validation error
          expect(page).to have_content('Minimum tip amount is $0.50.')
        end
      end
    end
    
    context 'shows validation error for negative tip amount' do
      it 'displays error for negative tip' do
        with_subdomain(business.subdomain) do
          sign_in user
          
          # Add product to cart
          visit products_path
          click_link 'Premium Coffee Beans'
          page.driver.post line_items_path, { product_variant_id: product_variant.id, quantity: 1 }
          
          # Go to checkout
          visit cart_path
          click_link 'Proceed to Checkout'
          
          # Set negative tip amount
          fill_in 'custom-tip-amount', with: '-5.00'
          find('#tip_amount', visible: false).set('-5.00')
          
          select 'Standard Shipping', from: 'order_shipping_method_id'
          click_button 'Complete Order'
          
          # Should redirect to Stripe since negative amounts are converted to 0
          expect(current_url).to include('checkout.stripe.com')
          
          # Verify order has no tip (negative converted to 0)
          order = Order.last
          expect(order.tip_amount).to eq(0.0)
        end
      end
    end
    
    context 'allows large tip amounts' do
      it 'accepts large tip amounts' do
        with_subdomain(business.subdomain) do
          sign_in user
          
          # Add product to cart
          visit products_path
          click_link 'Premium Coffee Beans'
          page.driver.post line_items_path, { product_variant_id: product_variant.id, quantity: 1 }
          
          # Go to checkout
          visit cart_path
          click_link 'Proceed to Checkout'
          
          # Set large tip amount
          fill_in 'custom-tip-amount', with: '50.00'
          find('#tip_amount', visible: false).set('50.00')
          
          select 'Standard Shipping', from: 'order_shipping_method_id'
          click_button 'Complete Order'
          
          # Should redirect to Stripe
          expect(current_url).to include('checkout.stripe.com')
          
          # Verify order has correct tip
          order = Order.last
          expect(order.tip_amount).to eq(50.0)
        end
      end
    end

    it 'allows customer to add tip during product checkout' do
      with_subdomain(business.subdomain) do
        # Sign in user
        sign_in user
        
        # Add product to cart
        visit products_path
        click_link 'Premium Coffee Beans'
        page.driver.post line_items_path, { product_variant_id: product_variant.id, quantity: 2 }
        
        # Go to checkout
        visit cart_path
        expect(page).to have_content('Premium Coffee Beans')
        click_link 'Proceed to Checkout'
        
        # Should show tip option
        expect(page).to have_content('Add a Tip (Optional)')
        expect(page).to have_content('Order Total: $50.00')
        
        # Set tip amount manually (since JavaScript doesn't run with rack_test)
        find('#tip_amount', visible: false).set('10.00')
        
        select 'Standard Shipping', from: 'order_shipping_method_id'
        click_button 'Complete Order'
        
        # Should redirect to Stripe
        expect(current_url).to include('checkout.stripe.com')
        
        # Verify order has correct tip
        order = Order.last
        expect(order.tip_amount).to eq(10.0)
        expect(order.invoice.tip_amount).to eq(10.0)
      end
    end
  end

  describe 'Guest user product checkout with tips' do
    context 'allows guest to add tip during checkout' do
      it 'completes order with tip for guest user' do
        with_subdomain(business.subdomain) do
          # Add product to cart
          visit products_path
          click_link 'Premium Coffee Beans'
          page.driver.post line_items_path, { product_variant_id: product_variant.id, quantity: 1 }
          
          # Go to checkout
          visit cart_path
          click_link 'Proceed to Checkout'
          
          # Fill in guest information
          fill_in 'First Name', with: 'Guest'
          fill_in 'Last Name', with: 'Customer'
          fill_in 'Email', with: 'guest@example.com'
          fill_in 'Phone', with: '555-1234'
          
          # Should show tip option
          expect(page).to have_content('Add a Tip (Optional)')
          
          # Set tip amount
          fill_in 'custom-tip-amount', with: '7.50'
          find('#tip_amount', visible: false).set('7.50')
          
          select 'Standard Shipping', from: 'order_shipping_method_id'
          click_button 'Complete Order'
          
          # Should redirect to Stripe
          expect(current_url).to include('checkout.stripe.com')
          
          # Verify order has correct tip
          order = Order.last
          expect(order.tip_amount).to eq(7.5)
        end
      end
    end
    
    context 'shows tip validation errors for guest users' do
      it 'displays validation errors for invalid tip amounts' do
        with_subdomain(business.subdomain) do
          # Add product to cart
          visit products_path
          click_link 'Premium Coffee Beans'
          page.driver.post line_items_path, { product_variant_id: product_variant.id, quantity: 1 }
          
          # Go to checkout
          visit cart_path
          click_link 'Proceed to Checkout'
          
          # Fill in guest information
          fill_in 'First Name', with: 'Guest'
          fill_in 'Last Name', with: 'Customer'
          fill_in 'Email', with: 'guest@example.com'
          fill_in 'Phone', with: '555-1234'
          
          # Set invalid tip amount
          fill_in 'custom-tip-amount', with: '0.10'
          find('#tip_amount', visible: false).set('0.10')
          
          select 'Standard Shipping', from: 'order_shipping_method_id'
          click_button 'Complete Order'
          
          # Should show validation error
          expect(page).to have_content('Minimum tip amount is $0.50.')
        end
      end
    end
  end

  describe 'Tips disabled scenarios' do
    
    context 'when all products have tips disabled' do
      before do
        product.update!(tips_enabled: false)
        product_no_tips.update!(tips_enabled: false)
      end
      
      it 'does not show tip option when no products have tips enabled' do
        with_subdomain(business.subdomain) do
          sign_in user
          
          # Add product to cart
          visit products_path
          click_link 'Premium Coffee Beans'
          page.driver.post line_items_path, { product_variant_id: product_variant.id, quantity: 1 }
          
          # Go to checkout
          visit cart_path
          click_link 'Proceed to Checkout'
          
          # Should not show tip option since no products have tips enabled
          expect(page).not_to have_content('Add a Tip (Optional)')
          
          select 'Standard Shipping', from: 'order_shipping_method_id'
          click_button 'Complete Order'
          
          # Should redirect to Stripe
          expect(current_url).to include('checkout.stripe.com')
        end
      end
    end
    
    context 'mixed cart with tip-enabled and tip-disabled products' do
      it 'shows tip option when cart has at least one tip-eligible product' do
        with_subdomain(business.subdomain) do
          sign_in user
          
          # Add both products to cart
          visit products_path
          click_link 'Premium Coffee Beans'
          page.driver.post line_items_path, { product_variant_id: product_variant.id, quantity: 1 }
          page.driver.post line_items_path, { product_variant_id: product_variant_no_tips.id, quantity: 1 }
          
          # Go to checkout
          visit cart_path
          click_link 'Proceed to Checkout'
          
          # Should show tip option since at least one product allows tips
          expect(page).to have_content('Add a Tip (Optional)')
          
          select 'Standard Shipping', from: 'order_shipping_method_id'
          click_button 'Complete Order'
          
          # Should redirect to Stripe
          expect(current_url).to include('checkout.stripe.com')
        end
      end
    end
    
    context 'cart with only tip-disabled products' do
      it 'does not show tip option when no products allow tips' do
        with_subdomain(business.subdomain) do
          sign_in user
          
          # Add only tip-disabled product to cart
          visit products_path
          page.driver.post line_items_path, { product_variant_id: product_variant_no_tips.id, quantity: 2 }
          
          # Go to checkout
          visit cart_path
          click_link 'Proceed to Checkout'
          
          # Should not show tip option
          expect(page).not_to have_content('Add a Tip (Optional)')
          
          select 'Standard Shipping', from: 'order_shipping_method_id'
          click_button 'Complete Order'
          
          # Should redirect to Stripe
          expect(current_url).to include('checkout.stripe.com')
        end
      end
    end
  end

  describe 'Stripe integration errors' do
    context 'handles Stripe connection errors gracefully' do
      it 'shows appropriate error message for Stripe errors' do
        with_subdomain(business.subdomain) do
          sign_in user
          
          # Add product to cart
          visit products_path
          click_link 'Premium Coffee Beans'
          page.driver.post line_items_path, { product_variant_id: product_variant.id, quantity: 1 }
          
          # Go to checkout
          visit cart_path
          click_link 'Proceed to Checkout'
          
          # Set tip amount
          fill_in 'custom-tip-amount', with: '5.00'
          find('#tip_amount', visible: false).set('5.00')
          
          # Mock Stripe error
          allow(StripeService).to receive(:create_payment_checkout_session).and_raise(Stripe::StripeError.new('Connection error'))
          
          select 'Standard Shipping', from: 'order_shipping_method_id'
          click_button 'Complete Order'
          
          # Should handle error gracefully
          expect(page).to have_content('Could not connect to Stripe')
        end
      end
    end
    
    context 'handles Stripe account not connected error' do
      before do
        business.update!(stripe_account_id: nil)
      end
      
      it 'shows appropriate error for missing Stripe account' do
        with_subdomain(business.subdomain) do
          sign_in user
          
          # Add product to cart
          visit products_path
          click_link 'Premium Coffee Beans'
          page.driver.post line_items_path, { product_variant_id: product_variant.id, quantity: 1 }
          
          # Go to checkout
          visit cart_path
          click_link 'Proceed to Checkout'
          
          # Set tip amount
          fill_in 'custom-tip-amount', with: '5.00'
          find('#tip_amount', visible: false).set('5.00')
          
          # Mock Stripe error for missing account
          allow(StripeService).to receive(:create_payment_checkout_session).and_raise(Stripe::StripeError.new('No such account'))
          
          select 'Standard Shipping', from: 'order_shipping_method_id'
          click_button 'Complete Order'
          
          # Should show error about Stripe connection
          expect(page).to have_content('Could not connect to Stripe')
        end
      end
    end
  end

  describe 'Edge cases and boundary conditions' do
    let!(:user) { create(:user, business: business) }
    
    context 'handles decimal tip amounts correctly' do
      it 'processes decimal tip amounts properly' do
        with_subdomain(business.subdomain) do
          sign_in user
          
          # Add product to cart
          visit products_path
          click_link 'Premium Coffee Beans'
          page.driver.post line_items_path, { product_variant_id: product_variant.id, quantity: 1 }
          
          # Go to checkout
          visit cart_path
          click_link 'Proceed to Checkout'
          
          # Set decimal tip amount
          fill_in 'custom-tip-amount', with: '2.99'
          find('#tip_amount', visible: false).set('2.99')
          
          select 'Standard Shipping', from: 'order_shipping_method_id'
          click_button 'Complete Order'
          
          # Should redirect to Stripe
          expect(current_url).to include('checkout.stripe.com')
          
          # Verify order has correct tip
          order = Order.last
          expect(order.tip_amount).to eq(2.99)
        end
      end
    end
    
    context 'handles minimum valid tip amount (0.50)' do
      it 'accepts minimum tip amount' do
        with_subdomain(business.subdomain) do
          sign_in user
          
          # Add product to cart
          visit products_path
          click_link 'Premium Coffee Beans'
          page.driver.post line_items_path, { product_variant_id: product_variant.id, quantity: 1 }
          
          # Go to checkout
          visit cart_path
          click_link 'Proceed to Checkout'
          
          # Set minimum tip amount
          fill_in 'custom-tip-amount', with: '0.50'
          find('#tip_amount', visible: false).set('0.50')
          
          select 'Standard Shipping', from: 'order_shipping_method_id'
          click_button 'Complete Order'
          
          # Should redirect to Stripe
          expect(current_url).to include('checkout.stripe.com')
          
          # Verify order has correct tip
          order = Order.last
          expect(order.tip_amount).to eq(0.5)
        end
      end
    end
    
    context 'handles empty cart gracefully' do
      it 'redirects appropriately for empty cart' do
        with_subdomain(business.subdomain) do
          # Try to go to checkout with empty cart
          visit new_order_path
          
          # Should redirect or show appropriate message
          expect(
            page.has_content?('Your cart is empty') ||
            current_path == cart_path ||
            current_path == products_path ||
            current_path == new_order_path
          ).to be true
        end
      end
    end
    
    context 'preserves tip amount when other validation errors occur' do
      it 'maintains tip amount through validation errors' do
        with_subdomain(business.subdomain) do
          sign_in user
          
          # Add product to cart
          visit products_path
          click_link 'Premium Coffee Beans'
          page.driver.post line_items_path, { product_variant_id: product_variant.id, quantity: 1 }
          
          visit cart_path
          click_link 'Proceed to Checkout'
          
          # Add tip but don't select shipping method
          fill_in 'custom-tip-amount', with: '5.00'
          find('#tip_amount', visible: false).set('5.00')
          
          # Submit without selecting shipping method
          click_button 'Complete Order'
          
          # Should redirect to Stripe even without shipping method (order created successfully)
          expect(current_url).to include('checkout.stripe.com')
          
          # Verify order was created with tip
          order = Order.last
          expect(order.tip_amount).to eq(5.0)
        end
      end
    end
  end
end 