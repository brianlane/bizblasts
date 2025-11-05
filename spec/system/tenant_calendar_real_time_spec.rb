require 'rails_helper'

RSpec.describe "Tenant Calendar Real-time Updates", type: :system do
  let!(:business) do
    create(:business, name: "Nocturnal Services", time_zone: 'America/Phoenix', subdomain: 'nocturnal')
  end
  let!(:service) { create(:service, business: business, duration: 30, name: 'Late Night Consultation') }
  let!(:service_variant) { create(:service_variant, service: service, duration: service.duration) }
  let!(:staff_member) { create(:staff_member, business: business, name: 'Night Owl') }
  let!(:client) { create(:user, :client) }

  before do
    # Associate service with staff
    create(:services_staff_member, service: service, staff_member: staff_member)
    # Associate client with business
    create(:client_business, user: client, business: business)

    # Bypass validation to set overnight availability (Wednesday 10 PM to Thursday 1 AM)
    staff_member.update!(
      availability: {
        'monday' => [],
        'tuesday' => [],
        'wednesday' => [{ 'start' => '22:00', 'end' => '23:59' }],
        'thursday' => [{ 'start' => '00:00', 'end' => '01:00' }],
        'friday' => [],
        'saturday' => [],
        'sunday' => []
      }
    )

    # Sign in as the client
    login_as(client, scope: :user)
  end

  it "displays the correct slot count for days with late-night availability as time passes", js: true do
    # Find the next Wednesday in business timezone
    wednesday = Date.current.in_time_zone(business.time_zone).to_date.next_occurring(:wednesday)

    # Travel to Wednesday morning to check the initial state
    travel_to wednesday.in_time_zone(business.time_zone).change(hour: 10) do
      with_subdomain(business.subdomain) do
        visit tenant_calendar_path(service_id: service.id, service_variant_id: service_variant.id)

        # Wait for calendar to fully render before finding elements
        expect(page).to have_css('.calendar-day', minimum: 1, wait: 10)

        # Initially, on Wednesday morning, the slot count for Wednesday should be greater than 0
        wednesday_cell = find(".calendar-day[data-date='#{wednesday.to_s}']", wait: 5)
        initial_count_span = wednesday_cell.find('.available-slots-count span')
        expect(initial_count_span.text.to_i).to be > 0
      end
    end

    # Now, travel to late that same night and revisit the page to test the JS update
    travel_to wednesday.in_time_zone(business.time_zone).change(hour: 22, min: 30) do
      with_subdomain(business.subdomain) do
        visit tenant_calendar_path(service_id: service.id, service_variant_id: service_variant.id)

        # Wait for calendar to fully render before finding elements
        expect(page).to have_css('.calendar-day', minimum: 1, wait: 10)

        # The page's JS will run a function to update the count.
        # We need to wait for it to potentially change.
        # With the fix, the count should remain greater than 0.
        wednesday_cell = find(".calendar-day[data-date='#{wednesday.to_s}']", wait: 5)
        late_night_count_span = wednesday_cell.find('.available-slots-count span')
        expect(late_night_count_span.text.to_i).to be > 0

        # For good measure, let's verify we can still click and see slots
        find(".calendar-day[data-date='#{wednesday.to_s}']", wait: 5).click
        expect(page).to have_selector('.slot-detail-overlay', visible: true)
        # At 10:30 PM, the 10:00 slot is gone, but 11:00 should be visible.
        expect(page).to have_content('11:00 PM')
        expect(page).not_to have_content('10:30 PM')
      end
    end
  end
end 