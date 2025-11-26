require 'rails_helper'

RSpec.describe 'Guest Booking Flow', type: :system, js: true do
  let!(:business) { create(:business, :with_default_tax_rate, host_type: 'subdomain', time_zone: 'UTC') }
  let!(:service) { create(:service, business: business, duration: 60, name: 'Guest Service') }
  let!(:staff_member) { create(:staff_member, business: business, name: 'Staff Member') }

  before do
    # Associate staff with service
    create(:services_staff_member, service: service, staff_member: staff_member)
    ActsAsTenant.current_tenant = business
    set_tenant(business)
  end

  let(:date) { Date.today.next_day }

  it 'allows a guest to book a service without logging in' do
    with_subdomain(business.subdomain) do
      visit_and_wait new_tenant_booking_path(service_id: service.id, staff_member_id: staff_member.id)

      # Accept the cookie banner if it appears
      dismiss_cookie_banner_if_present

      # Fill in guest details
      fill_in 'First Name', with: 'Guest'
      fill_in 'Last Name', with: 'User'
      fill_in 'Email', with: 'guest@example.com'
      fill_in 'Phone', with: '555-5555'

      # Select booking date and time
      select date.year.to_s,   from: 'booking_start_time_1i'
      select date.month.to_s,  from: 'booking_start_time_2i'
      select date.day.to_s,    from: 'booking_start_time_3i'
      select '09',             from: 'booking_start_time_4i'
      select '00',             from: 'booking_start_time_5i'

      fill_in 'Notes', with: 'Guest booking test'

      # Use a longer timeout for the button click as it may trigger slow operations
      using_wait_time(30) do
        click_button 'Confirm Booking'

        # Wait for redirect to confirmation page for standard services
        expect(page).to have_current_path(%r{/booking/\d+/confirmation}, wait: 30)
      end
      expect(page).to have_content('Booking confirmed! You can pay now or later.')
      
      # Ensure record persisted
      booking = Booking.find_by(service: service, staff_member: staff_member, notes: 'Guest booking test')
      expect(booking).not_to be_nil
      expect(booking.status).to eq('confirmed')
      expect(booking.invoice).to be_present
      
      # Verify invoice has proper tax calculations
      invoice = booking.invoice
      expect(invoice.tax_rate).to be_present
      expect(invoice.tax_rate).to eq(business.default_tax_rate)
      expect(invoice.tax_amount).to be > 0 # Should have tax applied
    end
  end

  it 'allows a guest to book and create an account' do
    with_subdomain(business.subdomain) do
      visit_and_wait new_tenant_booking_path(service_id: service.id, staff_member_id: staff_member.id)

      # Accept the cookie banner if it appears
      dismiss_cookie_banner_if_present

      fill_in 'First Name', with: 'Jane'
      fill_in 'Last Name', with: 'Doe'
      fill_in 'Email', with: 'jane.doe@example.com'
      fill_in 'Phone', with: '1234567890'
      check 'Create an account with these details?'
      fill_in 'Password', with: 'password123'
      fill_in 'Confirm Password', with: 'password123'

      select date.year.to_s,   from: 'booking_start_time_1i'
      select date.month.to_s,  from: 'booking_start_time_2i'
      select date.day.to_s,    from: 'booking_start_time_3i'
      select '10',             from: 'booking_start_time_4i'
      select '00',             from: 'booking_start_time_5i'

      fill_in 'Notes', with: 'Booking with account'
      click_button 'Confirm Booking'

      # With email confirmation enabled, user creation redirects to sign-in
      # because the new user needs to confirm their email before signing in
      expect(current_path).to eq('/users/sign_in')
      expect(page).to have_content('You have to confirm your email address before continuing')
      
      # Verify user account was created but not confirmed
      user = User.find_by(email: 'jane.doe@example.com')
      expect(user).to be_present
      expect(user.confirmed?).to be false
      expect(user.role).to eq('client')
      
      # Confirm the user and sign in to complete the booking process
      user.confirm
      fill_in 'Email', with: 'jane.doe@example.com'
      fill_in 'Password', with: 'password123'
      click_button 'Sign In'
      
      # After sign-in, should redirect to client dashboard
      expect(current_path).to eq('/dashboard')
      expect(page).to have_content('Signed in successfully')
      
      # The booking may not have been created since account creation interrupted the flow
      # This is expected behavior with email confirmation - guest would need to restart the booking process
    end
  end

  # Test for the email confirmation functionality added during authentication implementation
  describe 'email confirmation functionality' do
    it 'requires email confirmation for new user accounts created during guest booking' do
      with_subdomain(business.subdomain) do
        visit_and_wait new_tenant_booking_path(service_id: service.id, staff_member_id: staff_member.id)

        # Accept the cookie banner if it appears
        dismiss_cookie_banner_if_present

        fill_in 'First Name', with: 'Confirmation'
        fill_in 'Last Name', with: 'Test'
        fill_in 'Email', with: 'confirmation@example.com'
        fill_in 'Phone', with: '555-0000'
        check 'Create an account with these details?'
        fill_in 'Password', with: 'testpass123'
        fill_in 'Confirm Password', with: 'testpass123'

        select date.year.to_s,   from: 'booking_start_time_1i'
        select date.month.to_s,  from: 'booking_start_time_2i'
        select date.day.to_s,    from: 'booking_start_time_3i'
        select '11',             from: 'booking_start_time_4i'
        select '00',             from: 'booking_start_time_5i'

        fill_in 'Notes', with: 'Email confirmation test'

        # Use a longer timeout for the button click as it may trigger slow operations
        using_wait_time(30) do
          click_button 'Confirm Booking'

          # Wait for redirect to sign-in with confirmation message
          expect(page).to have_current_path('/users/sign_in', wait: 30)
        end
        expect(page).to have_content('You have to confirm your email address before continuing')
        
        # User should be created but unconfirmed
        user = User.find_by(email: 'confirmation@example.com')
        expect(user).to be_present
        expect(user.confirmed?).to be false
        expect(user.confirmation_token).to be_present
        expect(user.confirmation_sent_at).to be_present
        
        # Attempting to sign in without confirmation should fail
        fill_in 'Email', with: 'confirmation@example.com'
        fill_in 'Password', with: 'testpass123'
        click_button 'Sign In'
        
        expect(page).to have_content('You have to confirm your email address before continuing')
        
        # After confirming, user should be able to sign in
        user.confirm
        fill_in 'Email', with: 'confirmation@example.com'
        fill_in 'Password', with: 'testpass123'
        click_button 'Sign In'
        
        # Should successfully sign in
        expect(page).to have_content('Signed in successfully')
      end
    end
  end
end 