require 'rails_helper'

RSpec.describe 'Stripe Payment Flows', type: :system, js: true do
  include StripeWebhookHelpers
  
  let!(:business) { create(:business, subdomain: 'testbiz', hostname: 'testbiz', host_type: 'subdomain', tier: 'standard', stripe_account_id: 'acct_test123') }
  
  before do
    ActsAsTenant.current_tenant = business
    set_tenant(business)
    
    # Mock StripeService payment intent creation - will be called with the actual invoice
    allow(StripeService).to receive(:create_payment_intent) do |args|
      invoice = args[:invoice]
      
      if args[:payment_method_id].present?
        # This is the form submission - just return success
        { success: true }
      else
        # This is the initial payment intent creation for the form
        payment = create(:payment, stripe_payment_intent_id: 'pi_test123', business: business, invoice: invoice, order: invoice.order, amount: invoice.total_amount)
        {
          id: 'pi_test123',
          client_secret: 'pi_test123_secret',
          payment: payment
        }
      end
    end
  end

  context 'Client user books a service and redirects to Stripe' do
    let!(:service) { create(:service, business: business, name: 'Haircut', price: 50.00, duration: 30) }
    let!(:staff_member) { create(:staff_member, business: business, name: 'John Stylist') }
    let!(:user) { create(:user, :client, email: 'client@example.com', password: 'password123') }
    let!(:tenant_customer) { create(:tenant_customer, business: business, email: user.email, name: user.full_name) }
    
    before do
      create(:services_staff_member, service: service, staff_member: staff_member)
      # Mock Stripe checkout session creation
      allow(StripeService).to receive(:create_payment_checkout_session).and_return({
        session: double('Stripe::Checkout::Session', url: 'https://checkout.stripe.com/pay/cs_booking_123')
      })
    end

    it 'redirects directly to Stripe Checkout after booking' do
      with_subdomain('testbiz') do
        # Sign in
        visit new_user_session_path
        fill_in 'Email', with: user.email
        fill_in 'Password', with: 'password123'
        click_button 'Log in'
        
        # Book service
        visit new_tenant_booking_path(service_id: service.id, staff_member_id: staff_member.id)
        
        # Select date/time
        tomorrow = Date.tomorrow
        select tomorrow.year.to_s, from: 'booking_start_time_1i'
        select tomorrow.month.to_s, from: 'booking_start_time_2i'
        select tomorrow.day.to_s, from: 'booking_start_time_3i'
        select '10', from: 'booking_start_time_4i'
        select '00', from: 'booking_start_time_5i'
        
        click_button 'Confirm Booking'
        
        # Should redirect to Stripe (mocked)
        expect(current_url).to eq('https://checkout.stripe.com/pay/cs_booking_123')
        
        # Verify booking was created
        booking = Booking.last
        expect(booking).to be_present
        expect(booking.tenant_customer).to eq(tenant_customer)
        expect(booking.invoice).to be_present
        
        # Verify Stripe service was called with correct parameters
        expect(StripeService).to have_received(:create_payment_checkout_session).with(
          invoice: booking.invoice,
          success_url: "http://testbiz.lvh.me:9887/booking/#{booking.id}/confirmation?payment_success=true",
          cancel_url: "http://testbiz.lvh.me:9887/booking/#{booking.id}/confirmation?payment_cancelled=true"
        )
      end
    end
  end

  context 'Guest customer books a service and redirects to Stripe' do
    let!(:service) { create(:service, business: business, name: 'Massage', price: 80.00, duration: 60) }
    let!(:staff_member) { create(:staff_member, business: business, name: 'Jane Therapist') }
    
    before do
      create(:services_staff_member, service: service, staff_member: staff_member)
      # Mock Stripe checkout session creation
      allow(StripeService).to receive(:create_payment_checkout_session).and_return({
        session: double('Stripe::Checkout::Session', url: 'https://checkout.stripe.com/pay/cs_guest_booking_456')
      })
    end

    it 'redirects guest booking directly to Stripe Checkout' do
      with_subdomain('testbiz') do
        visit new_tenant_booking_path(service_id: service.id, staff_member_id: staff_member.id)
        
        # Fill guest details
        fill_in 'First Name', with: 'Guest'
        fill_in 'Last Name', with: 'Customer'
        fill_in 'Email', with: 'guest@example.com'
        fill_in 'Phone', with: '555-1234'
        
        # Select date/time
        tomorrow = Date.tomorrow
        select tomorrow.year.to_s, from: 'booking_start_time_1i'
        select tomorrow.month.to_s, from: 'booking_start_time_2i'
        select tomorrow.day.to_s, from: 'booking_start_time_3i'
        select '14', from: 'booking_start_time_4i'
        select '00', from: 'booking_start_time_5i'
        
        click_button 'Confirm Booking'
        
        # Should redirect to Stripe (mocked)
        expect(current_url).to eq('https://checkout.stripe.com/pay/cs_guest_booking_456')
        
        # Verify booking was created
        booking = Booking.last
        expect(booking).to be_present
        expect(booking.tenant_customer.email).to eq('guest@example.com')
        expect(booking.invoice).to be_present
      end
    end
  end

  context 'Client user purchases product and redirects to Stripe' do
    let!(:product) { create(:product, business: business, name: 'Shampoo', price: 25.00, active: true) }
    let!(:variant) { create(:product_variant, product: product, name: 'Large', stock_quantity: 10) }
    let!(:shipping_method) { create(:shipping_method, business: business, name: 'Standard', cost: 5.00) }
    let!(:user) { create(:user, :client, email: 'shopper@example.com', password: 'password123') }
    let!(:tenant_customer) { create(:tenant_customer, business: business, email: user.email, name: user.full_name) }

    before do
      # Mock Stripe checkout session creation for product orders
      allow(StripeService).to receive(:create_payment_checkout_session).and_return({
        session: double('Stripe::Checkout::Session', url: 'https://checkout.stripe.com/pay/cs_product_order_789')
      })
    end

    it 'redirects directly to Stripe Checkout for product orders' do
      with_subdomain('testbiz') do
        # Sign in
        visit new_user_session_path
        fill_in 'Email', with: user.email
        fill_in 'Password', with: 'password123'
        click_button 'Log in'
        
        # Add product to cart
        visit products_path
        click_link 'Shampoo'
        select 'Large', from: 'variant'
        fill_in 'quantity', with: 2
        click_button 'Add to Cart'
        
        # Checkout
        visit cart_path
        click_link 'Checkout'
        select 'Standard', from: 'Shipping Method'
        click_button 'Place Order'
        
        # Should redirect to Stripe (mocked)
        expect(current_url).to eq('https://checkout.stripe.com/pay/cs_product_order_789')
        
        # Verify order was created
        order = Order.last
        expect(order).to be_present
        expect(order.tenant_customer).to eq(tenant_customer)
        expect(order.invoice).to be_present
      end
    end
  end

  context 'Guest customer purchases product and redirects to Stripe' do
    let!(:product) { create(:product, business: business, name: 'Conditioner', price: 20.00, active: true) }
    let!(:variant) { create(:product_variant, product: product, name: 'Regular', stock_quantity: 5) }
    let!(:shipping_method) { create(:shipping_method, business: business, name: 'Express', cost: 10.00) }

    before do
      # Mock Stripe checkout session creation for guest product orders
      allow(StripeService).to receive(:create_payment_checkout_session).and_return({
        session: double('Stripe::Checkout::Session', url: 'https://checkout.stripe.com/pay/cs_guest_order_999')
      })
    end

    it 'redirects guest product orders directly to Stripe Checkout' do
      with_subdomain('testbiz') do
        # Add to cart as guest
        visit products_path
        click_link 'Conditioner'
        select 'Regular', from: 'variant'
        fill_in 'quantity', with: 1
        click_button 'Add to Cart'
        
        # Checkout
        visit cart_path
        click_link 'Checkout'
        
        # Fill guest info
        fill_in 'First Name', with: 'Guest'
        fill_in 'Last Name', with: 'Buyer'
        fill_in 'Email', with: 'buyer@example.com'
        fill_in 'Phone', with: '555-9999'
        select 'Express', from: 'Shipping Method'
        click_button 'Place Order'
        
        # Should redirect to Stripe (mocked)
        expect(current_url).to eq('https://checkout.stripe.com/pay/cs_guest_order_999')
        
        # Verify order was created
        order = Order.last
        expect(order).to be_present
        expect(order.tenant_customer.email).to eq('buyer@example.com')
        expect(order.invoice).to be_present
      end
    end
  end
end 