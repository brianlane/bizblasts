# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Stripe Payment Flows', type: :system, js: true do
  include StripeWebhookHelpers
  
  let!(:business) { create(:business, :with_default_tax_rate, host_type: 'subdomain', stripe_account_id: 'acct_test123') }
  
  before do
    ActsAsTenant.current_tenant = business
    set_tenant(business)
    Capybara.app_host = url_for_business(business)
    
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
    let!(:tenant_customer) { create(:tenant_customer, business: business, email: user.email, first_name: user.first_name, last_name: user.last_name) }
    
    before do
      create(:services_staff_member, service: service, staff_member: staff_member)
    end

    it 'creates booking and redirects to confirmation for standard services' do
      with_subdomain(business.subdomain) do
        # Sign in
        visit new_user_session_path
        fill_in 'Email', with: user.email
        fill_in 'Password', with: 'password123'
        click_button 'Sign In'
        
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
        
        # Should redirect to confirmation page for standard services
        expect(current_path).to match(%r{/booking/\d+/confirmation})
        expect(page).to have_content('Booking confirmed! You can pay now or later.')
        
        # Verify booking was created
        expect(Booking.count).to eq(1)
        booking = Booking.last
        expect(booking.status).to eq('confirmed')
        expect(booking.service).to eq(service)
        expect(booking.staff_member).to eq(staff_member)
        expect(booking.invoice).to be_present
        
        # Verify invoice has proper tax calculations
        invoice = booking.invoice
        expect(invoice.tax_rate).to be_present
        expect(invoice.tax_rate).to eq(business.default_tax_rate)
        expect(invoice.original_amount).to be_within(0.01).of(50.00)
        expect(invoice.tax_amount).to be_within(0.01).of(4.90) # 9.8% of $50
        expect(invoice.total_amount).to be_within(0.01).of(54.90) # $50 + $4.90 tax
      end
    end
  end

  context 'Guest customer books a service and redirects to Stripe' do
    let!(:service) { create(:service, business: business, name: 'Massage', price: 80.00, duration: 60) }
    let!(:staff_member) { create(:staff_member, business: business, name: 'Jane Therapist') }
    
    before do
      create(:services_staff_member, service: service, staff_member: staff_member)
    end

    it 'creates guest booking and redirects to confirmation for standard services' do
      with_subdomain(business.subdomain) do
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
        
        # Should redirect to confirmation page for standard services
        expect(current_path).to match(%r{/booking/\d+/confirmation})
        expect(page).to have_content('Booking confirmed! You can pay now or later.')
        
        # Verify booking was created
        expect(Booking.count).to eq(1)
        booking = Booking.last
        expect(booking.status).to eq('confirmed')
        expect(booking.service).to eq(service)
        expect(booking.staff_member).to eq(staff_member)
        expect(booking.invoice).to be_present
        
        # Verify invoice has proper tax calculations
        invoice = booking.invoice
        expect(invoice.tax_rate).to be_present
        expect(invoice.tax_rate).to eq(business.default_tax_rate)
        expect(invoice.original_amount).to be_within(0.01).of(80.00)
        expect(invoice.tax_amount).to be_within(0.01).of(7.84) # 9.8% of $80
        expect(invoice.total_amount).to be_within(0.01).of(87.84) # $80 + $7.84 tax
        
        # Verify customer was created
        customer = TenantCustomer.find_by(email: 'guest@example.com')
        expect(customer).to be_present
        expect(customer.full_name).to eq('Guest Customer')
      end
    end
  end

  context 'Client user purchases product and redirects to Stripe' do
    let!(:product) { create(:product, business: business, name: 'Shampoo', price: 25.00, active: true) }
    let!(:variant) { create(:product_variant, product: product, name: 'Large', stock_quantity: 10) }
    let!(:shipping_method) { create(:shipping_method, business: business, name: 'Standard', cost: 5.00) }
    let!(:user) { create(:user, :client, email: 'shopper@example.com', password: 'password123') }
    let!(:tenant_customer) { create(:tenant_customer, business: business, email: user.email, first_name: user.first_name, last_name: user.last_name) }

    before do
      # Mock Stripe checkout session creation for product orders
      allow(StripeService).to receive(:create_payment_checkout_session).and_return({
        session: double('Stripe::Checkout::Session', url: 'https://checkout.stripe.com/pay/cs_product_order_789')
      })
    end

    it 'redirects directly to Stripe Checkout for product orders' do
      with_subdomain(business.subdomain) do
        # Sign in
        visit new_user_session_path

        # Dismiss cookie banner if it appears (more robust check)
        begin
          if page.has_button?('Accept', wait: 2)
            click_button 'Accept'
          end
        rescue Capybara::ElementNotFound
          # Banner might not appear in CI - continue with test
        end

        fill_in 'Email', with: user.email
        fill_in 'Password', with: 'password123'
        click_button 'Sign In'
        
        # Add product to cart
        visit products_path
        click_link 'Shampoo'
        
        # Use the new JavaScript dropdown structure
        find('#product_variant_dropdown [data-dropdown-target="button"]').click
        find('#product_variant_dropdown [data-dropdown-target="option"]', text: 'Large').click
        
        fill_in 'quantity', with: 2
        click_button 'Add to Cart'
        
        # Checkout
        visit cart_path
        click_link 'Checkout'
        select 'Standard', from: 'Select shipping method'
        click_button 'Complete Order'
        
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
      with_subdomain(business.subdomain) do
        # Add to cart as guest
        visit products_path

        # Dismiss cookie banner if it appears (more robust check)
        begin
          if page.has_button?('Accept', wait: 2)
            click_button 'Accept'
          end
        rescue Capybara::ElementNotFound
          # Banner might not appear in CI - continue with test
        end

        click_link 'Conditioner'
        
        # Use the new JavaScript dropdown structure
        find('#product_variant_dropdown [data-dropdown-target="button"]').click
        find('#product_variant_dropdown [data-dropdown-target="option"]', text: 'Regular').click
        
        fill_in 'quantity', with: 1
        click_button 'Add to Cart'
        
        # Checkout
        visit cart_path

        # Dismiss cookie banner again if it appears before placing order
        begin
          if page.has_button?('Accept', wait: 2)
            click_button 'Accept'
          end
        rescue Capybara::ElementNotFound
          # Banner might not appear in CI - continue with test
        end

        click_link 'Checkout'
        
        # Fill guest info
        fill_in 'First Name', with: 'Guest'
        fill_in 'Last Name', with: 'Buyer'
        fill_in 'Email', with: 'buyer@example.com'
        fill_in 'Phone', with: '555-9999'
        select 'Express', from: 'Select shipping method'
        
        # Dismiss cookie banner one more time if it appears before placing order
        begin
          if page.has_button?('Accept', wait: 2)
            click_button 'Accept'
          end
        rescue Capybara::ElementNotFound
          # Banner might not appear - continue with test
        end
        
        click_button 'Complete Order'
        
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