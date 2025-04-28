require 'rails_helper'

RSpec.describe CalendarSyncService, type: :service do
  describe '#sync_booking' do
    it 'should sync a booking with the calendar service' do
      # Create a mock booking
      booking = double('Booking', 
                       bookable_type: 'StaffMember',
                       bookable: double('StaffMember'),
                       update: true)
      
      # Call the service method
      result = CalendarSyncService.sync_booking_to_provider(booking)
      
      # Verify the result was successful
      expect(result[:success]).to be true
      expect(result[:event_id]).not_to be_nil
      
      # Verify the booking was updated with the calendar event ID
      expect(booking).to have_received(:update).with(hash_including(:calendar_event_id))
    end
  end
end