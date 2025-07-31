# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Calendar::GoogleService, type: :service do
  let(:business) { create(:business) }
  let(:staff_member) { create(:staff_member, business: business) }
  let(:calendar_connection) { create(:calendar_connection, :google, staff_member: staff_member, business: business) }

  # Stub Google API so we don't hit the network
  before do
    allow_any_instance_of(described_class).to receive(:setup_authorization)
  end

  describe '#import_events' do
    let(:service) { described_class.new(calendar_connection) }

    let(:start_date) { Date.current }
    let(:end_date) { 30.days.from_now.to_date }

    let(:google_event1) do
      {
        external_event_id: 'evt_1',
        external_calendar_id: 'primary',
        starts_at: start_date.beginning_of_day + 10.hours,
        ends_at:   start_date.beginning_of_day + 11.hours,
        summary: 'Existing'
      }
    end

    let(:google_event2) do
      {
        external_event_id: 'evt_2',
        external_calendar_id: 'primary',
        starts_at: start_date.beginning_of_day + 12.hours,
        ends_at:   start_date.beginning_of_day + 13.hours,
        summary: 'New'
      }
    end

    before do
      # Pretend previous sync created event1 only
      ExternalCalendarEvent.import_for_connection(calendar_connection, [google_event1])

      # Stub fetch_google_events to now return event2 only (so event1 is stale)
      allow_any_instance_of(described_class).to receive(:fetch_google_events)
        .with(start_date, end_date)
        .and_return([google_event2])
    end

    it 'creates new events and prunes stale events' do
      expect {
        service.import_events(start_date, end_date)
      }.to change { ExternalCalendarEvent.count }.by(0) # one removed, one added

      ids = calendar_connection.external_calendar_events.pluck(:external_event_id)
      expect(ids).to contain_exactly('evt_2')
    end
  end
end