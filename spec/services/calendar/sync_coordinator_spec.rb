# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Calendar::SyncCoordinator, type: :service do
  let(:business) { create(:business) }
  let(:staff_member) { create(:staff_member, business: business) }
  let(:service) { create(:service, business: business) }
  let(:customer) { create(:tenant_customer, business: business) }
  let(:booking) { create(:booking, business: business, staff_member: staff_member, service: service, tenant_customer: customer) }
  let(:sync_coordinator) { described_class.new }
  
  before do
    ActsAsTenant.current_tenant = business
  end
  
  describe '#sync_booking' do
    context 'when staff member has no calendar connections' do
      it 'returns true immediately' do
        expect(sync_coordinator.sync_booking(booking)).to be true
      end
    end
    
    context 'when staff member has calendar connections' do
      let!(:calendar_connection) { create(:calendar_connection, business: business, staff_member: staff_member, provider: 'google', active: true) }
      
      before do
        allow_any_instance_of(Calendar::GoogleService).to receive(:create_event).and_return({
          success: true,
          external_event_id: 'google_event_123',
          mapping: double('mapping')
        })
      end
      
      it 'syncs booking to connected calendars' do
        expect(sync_coordinator.sync_booking(booking)).to be true
      end
      
      it 'updates booking calendar status' do
        sync_coordinator.sync_booking(booking)
        expect(booking.reload.calendar_event_status).to eq('synced')
      end
    end
    
    context 'when sync fails' do
      let!(:calendar_connection) { create(:calendar_connection, business: business, staff_member: staff_member, provider: 'google', active: true) }
      
      before do
        allow_any_instance_of(Calendar::GoogleService).to receive(:create_event).and_return(nil)
        allow_any_instance_of(Calendar::GoogleService).to receive(:errors).and_return(
          double('errors', full_messages: ['API Error'])
        )
      end
      
      it 'returns false' do
        expect(sync_coordinator.sync_booking(booking)).to be false
      end
      
      it 'updates booking status to failed' do
        sync_coordinator.sync_booking(booking)
        expect(booking.reload.calendar_event_status).to eq('sync_failed')
      end
    end
  end
  
  describe '#import_availability' do
    let!(:calendar_connection) { create(:calendar_connection, business: business, staff_member: staff_member, provider: 'google', active: true) }
    
    before do
      allow_any_instance_of(Calendar::GoogleService).to receive(:import_events).and_return({
        success: true,
        imported_count: 5,
        errors: []
      })
    end
    
    it 'imports events from connected calendars' do
      result = sync_coordinator.import_availability(staff_member)
      expect(result).to be true
    end
    
    it 'works with date range' do
      start_date = Date.current
      end_date = 1.week.from_now.to_date
      
      result = sync_coordinator.import_availability(staff_member, start_date, end_date)
      expect(result).to be true
    end
  end
  
  describe '#sync_statistics' do
    it 'returns statistics hash' do
      stats = sync_coordinator.sync_statistics(business)
      
      expect(stats).to be_a(Hash)
      expect(stats).to have_key(:total_attempts)
      expect(stats).to have_key(:successful)
      expect(stats).to have_key(:failed)
      expect(stats).to have_key(:success_rate)
    end
  end
  
  describe 'error handling' do
    let!(:calendar_connection) { create(:calendar_connection, business: business, staff_member: staff_member, provider: 'google', active: true) }
    
    it 'handles service initialization errors gracefully' do
      allow(Calendar::GoogleService).to receive(:new).and_raise(StandardError, 'Connection failed')
      
      result = sync_coordinator.sync_booking(booking)
      expect(result).to be false
    end
    
    it 'handles invalid booking gracefully' do
      result = sync_coordinator.sync_booking(nil)
      expect(result).to be false
    end
  end
end