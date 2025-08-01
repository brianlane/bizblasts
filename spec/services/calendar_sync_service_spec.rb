require 'rails_helper'

RSpec.describe CalendarSyncService, type: :service do
  let(:business) { create(:business) }
  let(:staff_member) { create(:staff_member, business: business) }
  let(:service) { create(:service, business: business) }
  let(:customer) { create(:tenant_customer, business: business) }
  let(:booking) { create(:booking, business: business, staff_member: staff_member, service: service, tenant_customer: customer) }
  
  before do
    ActsAsTenant.current_tenant = business
  end

  describe '#sync_booking' do
    context 'when staff member has no calendar connections' do
      it 'should sync a booking with the calendar service' do
        # Call the legacy service method - should return success when no calendars to sync
        result = CalendarSyncService.sync_booking_to_provider(booking)
        
        # Verify the result was successful (no calendars = success)
        expect(result[:success]).to be true
        expect(result[:event_id]).to eq(booking.calendar_event_id)
      end
    end

    context 'when staff member has calendar connections' do
      let!(:calendar_connection) { create(:calendar_connection, business: business, staff_member: staff_member, provider: 'google', active: true) }
      
      before do
        # Mock the Google service to simulate successful sync
        allow_any_instance_of(Calendar::GoogleService).to receive(:create_event).and_return({
          success: true,
          external_event_id: 'google_event_123',
          mapping: double('mapping')
        })
      end
      
      it 'should sync a booking to connected calendars' do
        result = CalendarSyncService.sync_booking_to_provider(booking)
        
        expect(result[:success]).to be true
        expect(result[:event_id]).to eq(booking.calendar_event_id)
      end
    end
  end
end