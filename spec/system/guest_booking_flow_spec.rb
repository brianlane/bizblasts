require 'rails_helper'

RSpec.describe 'Guest Booking Flow', type: :system, js: true do
  let!(:business) { create(:business, hostname: 'guestbiz', subdomain: 'guestbiz', host_type: 'subdomain', time_zone: 'UTC') }
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
    with_subdomain('guestbiz') do
      visit new_tenant_booking_path(service_id: service.id, staff_member_id: staff_member.id)

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
      click_button 'Confirm Booking'

      # Verify booking confirmation
      expect(page).to have_content('Booking was successfully created.')
      # Ensure record persisted
      booking = Booking.find_by(service: service, staff_member: staff_member, notes: 'Guest booking test')
      expect(booking).not_to be_nil
    end
  end

  it 'allows a guest to book and create an account' do
    with_subdomain('guestbiz') do
      visit new_tenant_booking_path(service_id: service.id, staff_member_id: staff_member.id)

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

      expect(page).to have_content('Booking was successfully created.')
      # Ensure user is created and signed in
      expect(User.find_by(email: 'jane.doe@example.com')).to be_present
    end
  end
end 