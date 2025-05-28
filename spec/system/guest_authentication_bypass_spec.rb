require 'rails_helper'

RSpec.describe 'Guest Authentication Bypass', type: :system, js: true do
  let!(:business) { create(:business, :with_default_tax_rate, hostname: 'guestbiz', subdomain: 'guestbiz', host_type: 'subdomain') }
  let!(:service) { create(:service, business: business, duration: 60, name: 'Test Service') }
  let!(:staff_member) { create(:staff_member, business: business, name: 'Staff Member') }
  let!(:product) { create(:product, name: 'Test Product', active: true, business: business) }
  let!(:variant) { create(:product_variant, product: product, name: 'Default', stock_quantity: 5) }

  before do
    # Associate staff with service
    create(:services_staff_member, service: service, staff_member: staff_member)
    switch_to_subdomain('guestbiz')
  end

  describe 'Public::BookingController authentication bypass' do
    it 'allows guests to access booking forms without signing in' do
      visit new_tenant_booking_path(service_id: service.id, staff_member_id: staff_member.id)
      
      # Should NOT redirect to sign-in page (allow flexible paths)
      expect(current_path).to include('/book')
      expect(page).not_to have_content('You need to sign in')
      
      # Should show booking form
      expect(page).to have_content('Book Your Appointment')
      expect(page).to have_field('First Name')
      expect(page).to have_field('Last Name')
      expect(page).to have_field('Email')
    end

    it 'allows guests to create bookings without signing in' do
      visit new_tenant_booking_path(service_id: service.id, staff_member_id: staff_member.id)
      
      # Fill in guest details (no account creation)
      fill_in 'First Name', with: 'Guest'
      fill_in 'Last Name', with: 'User'
      fill_in 'Email', with: 'guest@example.com'
      fill_in 'Phone', with: '555-5555'

      # Select booking date and time
      date = Date.today.next_day
      select date.year.to_s,   from: 'booking_start_time_1i'
      select date.month.to_s,  from: 'booking_start_time_2i'
      select date.day.to_s,    from: 'booking_start_time_3i'
      select '09',             from: 'booking_start_time_4i'
      select '00',             from: 'booking_start_time_5i'

      fill_in 'Notes', with: 'Guest booking test'
      click_button 'Confirm Booking'

      # Should successfully create booking and redirect to confirmation
      expect(current_path).to match(%r{/booking/\d+/confirmation})
      expect(page).to have_content('Booking confirmed')
      
      # Verify booking was created
      booking = Booking.find_by(notes: 'Guest booking test')
      expect(booking).to be_present
      expect(booking.tenant_customer.email).to eq('guest@example.com')
    end
  end

  describe 'Public::OrdersController authentication bypass' do
    it 'allows guests to access product pages and add to cart' do
      visit products_path
      
      # Should NOT redirect to sign-in page
      expect(current_path).to eq(products_path)
      expect(page).not_to have_content('You need to sign in')
      
      # Should show products
      expect(page).to have_content('Test Product')
      
      # Should be able to add to cart
      click_link 'Test Product'
      find('#variant').find("option[value='#{variant.id}']").select_option
      fill_in 'quantity', with: 1
      click_button 'Add to Cart'
      
      # Should successfully add to cart
      expect(page).to have_content('Item added to cart')
    end

    it 'allows guests to view cart and proceed to checkout' do
      # Add item to cart first
      visit products_path
      click_link 'Test Product'
      find('#variant').find("option[value='#{variant.id}']").select_option
      fill_in 'quantity', with: 1
      click_button 'Add to Cart'
      
      # View cart
      visit cart_path
      expect(current_path).to eq(cart_path)
      expect(page).to have_content('Test Product')
      
      # Proceed to checkout
      click_link 'Checkout'
      expect(current_path).to eq(new_order_path)
      expect(page).to have_field('First Name')
      expect(page).to have_field('Email')
    end
  end

  describe 'Authentication bypass configuration' do
    it 'correctly allows guest access to booking and cart functionality' do
      # Test that guests can access booking without authentication
      visit new_tenant_booking_path(service_id: service.id, staff_member_id: staff_member.id)
      expect(current_path).to include('/book')
      expect(page).not_to have_content('sign in')
      
      # Test that guests can access products without authentication  
      visit products_path
      expect(current_path).to eq(products_path)
      expect(page).not_to have_content('sign in')
    end
  end
end 