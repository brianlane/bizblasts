# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Invoice UI navigation after booking and Stripe payment', type: :system do
  let!(:business) { create(:business, :with_default_tax_rate, host_type: 'subdomain', stripe_account_id: 'acct_test123') }
  let!(:service) { create(:service, business: business, name: 'Test Service', price: 100.00, duration: 60) }
  let!(:staff_member) { create(:staff_member, business: business, name: 'Test Staff') }
  let!(:tenant_customer) { create(:tenant_customer, business: business, email: 'guest@example.com', first_name: 'Guest', last_name: 'Customer') }

  before do
    ActsAsTenant.current_tenant = business
    driven_by(:cuprite)
    
    # Create staff-service association
    create(:services_staff_member, service: service, staff_member: staff_member)
    
    # Mock Stripe service for payment processing - will be set up in individual tests
    
    switch_to_subdomain(business.subdomain)
  end

  it "completes booking flow, processes payment, and navigates back from paid invoice" do
    # Step 1: Create a booking as guest (no sign in)
    visit new_tenant_booking_path(service_id: service.id, staff_member_id: staff_member.id)
    
    # Fill in guest customer details
    fill_in 'First Name', with: tenant_customer.first_name
    fill_in 'Last Name', with: tenant_customer.last_name  
    fill_in 'Email', with: tenant_customer.email
    fill_in 'Phone', with: '555-1234'
    
    # Select date/time for booking
    tomorrow = Date.tomorrow
    select tomorrow.year.to_s, from: 'booking_start_time_1i'
    select tomorrow.month.to_s, from: 'booking_start_time_2i'
    select tomorrow.day.to_s, from: 'booking_start_time_3i'
    select '10', from: 'booking_start_time_4i'
    select '00', from: 'booking_start_time_5i'
    
    fill_in 'Notes', with: 'Test booking for payment flow'
    click_button 'Confirm Booking'
    
    # Should redirect to confirmation page (for standard services)
    expect(current_path).to match(%r{/booking/\d+/confirmation})
    expect(page).to have_content('Booking confirmed! You can pay now or later.')
    
    # Verify booking was created
    booking = Booking.last
    expect(booking.service).to eq(service)
    expect(booking.staff_member).to eq(staff_member)
    expect(booking.tenant_customer.email).to eq(tenant_customer.email)
    expect(booking.status).to eq('confirmed')
    expect(booking.invoice).to be_present
    
    # Step 2: Pay the invoice
    invoice = booking.invoice
    expect(invoice.status).to eq('pending')
    
    # Set up the mock BEFORE visiting the payment page
    expect(StripeService).to receive(:create_payment_checkout_session).with(
      invoice: invoice,
      success_url: anything,
      cancel_url: anything
    ).and_return({
      session: double('Stripe::Checkout::Session', url: 'https://checkout.stripe.com/pay/cs_test_123')
    })
    
    # Visit the invoice payment page
    visit tenant_invoice_path(invoice, access_token: invoice.guest_access_token)
    expect(page).to have_content('Invoice')
    expect(page).to have_content(/Status.*Pending/i)
    
    # Test direct navigation to payments URL to see what happens
    payment_url = new_tenant_payment_path(invoice_id: invoice.id)
    
    visit payment_url
    
    # Should redirect to Stripe checkout (mocked)
    expect(current_url).to eq('https://checkout.stripe.com/pay/cs_test_123')
    
    # Step 3: Simulate successful payment completion
    # This simulates what happens when Stripe webhook processes the payment
    ActsAsTenant.with_tenant(business) do
      # Create payment record using the actual tenant_customer from the booking
      payment = create(:payment, 
        business: business,
        invoice: invoice,
        tenant_customer: booking.tenant_customer,
        amount: invoice.total_amount,
        stripe_payment_intent_id: 'pi_test123',
        status: :completed,
        paid_at: Time.current
      )
      
      # Mark invoice as paid
      invoice.update!(status: :paid)
    end
    
    # Step 4: Test back button navigation after successful payment
    # In real Stripe flow, user might use back button or be redirected back
    page.go_back # Simulate clicking the back button (browser history) 

    # The invoice page should already reflect the paid status without a manual refresh
    expect(page).to have_content(/Status.*Paid/i)
    expect(page).to_not have_content('Pay $') # Payment button should be gone
    
    # Verify payment record exists
    payment = Payment.find_by(invoice: invoice)
    expect(payment).to be_present
    expect(payment.status).to eq('completed')
    expect(payment.amount).to eq(invoice.total_amount)
  end
end 