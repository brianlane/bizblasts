require 'rails_helper'

RSpec.describe 'Stripe Payment Flows', type: :system, js: true do
  include StripeWebhookHelpers
  
  let!(:business) { create(:business, subdomain: 'testbiz', hostname: 'testbiz', host_type: 'subdomain', tier: 'standard') }
  
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

  context 'Client user books a service and pays' do
    let!(:service) { create(:service, business: business, name: 'Haircut', price: 50.00, duration: 30) }
    let!(:staff_member) { create(:staff_member, business: business, name: 'John Stylist') }
    let!(:user) { create(:user, :client, email: 'client@example.com', password: 'password123') }
    let!(:tenant_customer) { create(:tenant_customer, business: business, email: user.email, name: user.full_name) }
    
    before do
      create(:services_staff_member, service: service, staff_member: staff_member)
    end

    it 'allows booking and optional payment' do
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
        
        # Should see confirmation with Pay Now option
        expect(page).to have_content('Booking Confirmed!')
        expect(page).to have_content('Haircut')
        
        # Debug: Check if invoice exists
        booking = Booking.last
        
        expect(page).to have_link('Pay Now')
        
        # Click Pay Now
        click_link 'Pay Now'
        
        # Mock payment form submission
        expect(page).to have_css('#payment-form')
        
        # Inject hidden payment_method_id and submit
        page.execute_script("
          const form = document.getElementById('payment-form');
          const input = document.createElement('input');
          input.type = 'hidden';
          input.name = 'payment_method_id';
          input.value = 'pm_test123';
          form.appendChild(input);
        ")
        
        # Click the submit button
        click_button 'Pay'
        
        # Should see success message
        expect(page).to have_content('Payment submitted successfully.')
        
        # Simulate webhook to mark as paid
        booking = Booking.last
        payment = Payment.last
        # Process webhook synchronously in test
        StripeService.handle_successful_payment({
          'id' => payment.stripe_payment_intent_id,
          'charges' => {
            'data' => [{
              'payment_method_details' => {
                'type' => 'card'
              }
            }]
          }
        })
        
        # Verify invoice is paid
        expect(booking.invoice.reload.status).to eq('paid')
      end
    end
  end

  context 'Tenant customer books a service and pays' do
    let!(:service) { create(:service, business: business, name: 'Massage', price: 80.00, duration: 60) }
    let!(:staff_member) { create(:staff_member, business: business, name: 'Jane Therapist') }
    
    before do
      create(:services_staff_member, service: service, staff_member: staff_member)
    end

    it 'allows guest booking with optional payment' do
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
        
        # Should see confirmation
        expect(page).to have_content('Booking Confirmed!')
        expect(page).to have_content('Massage')
        expect(page).to have_link('Pay Now')
        
        # Guest can choose to pay later - just verify the option exists
        expect(page).to have_content('You can complete payment now')
      end
    end
  end

  context 'Client user purchases product and must pay immediately' do
    let!(:product) { create(:product, business: business, name: 'Shampoo', price: 25.00, active: true) }
    let!(:variant) { create(:product_variant, product: product, name: 'Large', stock_quantity: 10) }
    let!(:shipping_method) { create(:shipping_method, business: business, name: 'Standard', cost: 5.00) }
    let!(:user) { create(:user, :client, email: 'shopper@example.com', password: 'password123') }
    let!(:tenant_customer) { create(:tenant_customer, business: business, email: user.email, name: user.full_name) }

    it 'requires immediate payment for product orders' do
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
        
        # Should be redirected directly to payment page
        expect(page).to have_content('Please complete payment to confirm your order')
        expect(page).to have_css('#payment-form')
        
        # Mock payment
        page.execute_script("
          const form = document.getElementById('payment-form');
          const input = document.createElement('input');
          input.type = 'hidden';
          input.name = 'payment_method_id';
          input.value = 'pm_test456';
          form.appendChild(input);
        ")
        
        # Click the submit button
        click_button 'Pay'
        
        expect(page).to have_content('Payment submitted successfully.')
        
        # Simulate webhook
        order = Order.last
        payment = Payment.last
        # Process webhook synchronously in test
        StripeService.handle_successful_payment({
          'id' => payment.stripe_payment_intent_id,
          'charges' => {
            'data' => [{
              'payment_method_details' => {
                'type' => 'card'
              }
            }]
          }
        })
        
        # Verify order is paid
        expect(order.reload.status).to eq('paid')
      end
    end
  end

  context 'Tenant customer purchases product and must pay immediately' do
    let!(:product) { create(:product, business: business, name: 'Conditioner', price: 20.00, active: true) }
    let!(:variant) { create(:product_variant, product: product, name: 'Regular', stock_quantity: 5) }
    let!(:shipping_method) { create(:shipping_method, business: business, name: 'Express', cost: 10.00) }

    it 'requires immediate payment for guest product orders' do
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
        
        # Should redirect to payment
        expect(page).to have_content('Please complete payment to confirm your order')
        expect(page).to have_css('#payment-form')
        
        # Verify order is pending_payment
        order = Order.last
        expect(order.status).to eq('pending_payment')
        expect(order.stock_reservations.count).to eq(1)
      end
    end
  end
end 