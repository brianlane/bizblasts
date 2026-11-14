# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Public::BookingController, type: :controller do
  render_views

  let(:business) { create(:business, time_zone: 'America/Phoenix') }
  let(:service) { create(:service, business: business, name: 'Reiki', duration: 60, price: 80) }
  let(:staff_member) { create(:staff_member, business: business, name: 'Samantha Hawley') }

  before do
    described_class.layout false
    ActsAsTenant.current_tenant = business
    request.host = host_for(business)
    create(:services_staff_member, service: service, staff_member: staff_member)
    Rails.cache.clear
  end

  after do
    described_class.layout 'application'
  end

  around do |example|
    travel_to(Time.find_zone('America/Phoenix').local(2026, 11, 18, 8, 0)) { example.run }
  end

  describe 'GET #new' do
    it 'offers only open slots from the calendar availability and no free-form time dropdown' do
      get :new, params: { service_id: service.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Available times')
      expect(response.body).to include('9:00 AM')
      expect(response.body).to include('Samantha Hawley')
      expect(response.body).not_to include('name="booking[start_time(1i)]"')
      expect(response.body).not_to include('23:45')

      offered = offered_slot_times(response.body)
      expect(offered).not_to be_empty
      local_times = offered.map { |time| time.in_time_zone('America/Phoenix') }
      expect(local_times.map(&:hour)).to all(be_between(9, 16))
      expect(local_times.map(&:to_date).uniq).to eq([Date.new(2026, 11, 18)])
      expect(response.body).to include('picker_date=2026-11-30')
    end

    it 'uses the selected variant duration, not the service duration' do
      create(:service_variant, service: service, name: 'Longer session', duration: 45, position: 1)

      get :new, params: { service_id: service.id }

      zone = Time.find_zone('America/Phoenix')
      offered = offered_slot_times(response.body).map { |time| time.in_time_zone(zone).change(sec: 0) }
      expect(offered).to eq(expected_starts(zone, step: 45, length: 60))
    end

    it 'shows an event only at its scheduled start, not on the staff grid' do
      event_start = Time.find_zone('America/Phoenix').local(2026, 11, 21, 19, 30)
      event = create(:service, :event, business: business, name: 'Evening Circle', duration: 60,
                                       event_starts_at: event_start)
      create(:services_staff_member, service: event, staff_member: staff_member)

      get :new, params: { service_id: event.id }

      expect(response.body).to include('Saturday, November 21, 2026 at 7:30 PM')
      expect(response.body).to include('one scheduled start time')
      expect(response.body).not_to include('name="booking[slot_choice]"')
      expect(response.body).not_to include('9:00 AM')
    end

    it 'waits for an option when several variants exist' do
      create(:service_variant, service: service, name: 'Short', duration: 30, position: 1)
      create(:service_variant, service: service, name: 'Long', duration: 90, position: 2)

      get :new, params: { service_id: service.id }

      expect(response.body).to include('Choose an option above to see open times.')
      expect(response.body).not_to include('name="booking[slot_choice]"')
    end

    it 'keeps a preselected calendar slot and offers a way to change it' do
      get :new, params: {
        service_id: service.id,
        staff_member_id: staff_member.id,
        date: '2026-11-18',
        start_time: '10:00'
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Wednesday, November 18, 2026 at 10:00 AM')
      expect(response.body).to include('Samantha Hawley')
      expect(response.body).to include('Change time')
      expect(response.body).not_to include('name="booking[start_time(1i)]"')
      expect(response.body).to include('name="booking[start_time]"')
    end
  end

  describe 'POST #create' do
    let(:guest) do
      {
        first_name: 'Ada',
        last_name: 'Lovelace',
        email: 'ada@example.com',
        phone: '555-123-4567'
      }
    end

    it 'rejects a time that is not an open slot' do
      expect {
        post :create, params: {
          booking: {
            service_id: service.id,
            staff_member_id: staff_member.id,
            start_time: Time.find_zone('America/Phoenix').local(2026, 11, 14, 23, 45).iso8601,
            tenant_customer_attributes: guest
          }
        }
      }.not_to change(Booking, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Please choose an open time')
      expect(response.body).not_to include('name="booking[start_time(1i)]"')
    end

    it 'accepts a slot the calendar would offer' do
      slot = Time.find_zone('America/Phoenix').local(2026, 11, 18, 10, 0)

      expect {
        post :create, params: {
          booking: {
            service_id: service.id,
            slot_choice: "#{slot.iso8601}|#{staff_member.id}",
            tenant_customer_attributes: guest
          }
        }
      }.to change(Booking, :count).by(1)

      booking = Booking.last
      expect(booking.start_time).to be_within(1.second).of(slot)
      expect(booking.staff_member).to eq(staff_member)
    end
  end

  def offered_slot_times(body)
    body.scan(/name="booking\[slot_choice\]"\s+value="([^"|]+)/).flatten.map { |value| Time.iso8601(value) }
  end

  def expected_starts(zone, step:, length:)
    starts = []
    cursor = zone.local(2026, 11, 18, 9, 0)
    closing = zone.local(2026, 11, 18, 17, 0)
    while cursor + length.minutes <= closing
      starts << cursor
      cursor += step.minutes
    end
    starts
  end
end
