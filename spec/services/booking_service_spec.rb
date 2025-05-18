require 'rails_helper'

RSpec.describe BookingService do
  let(:staff_member) { create(:staff_member) }
  let(:service) { create(:service) }
  let(:date) { Date.today }
  let(:tenant) { create(:business) }
  
  describe '.generate_calendar_data' do
    it 'returns calendar data with dates as keys' do
      # Mock the AvailabilityService
      allow(AvailabilityService).to receive(:available_slots).and_return([])
      
      # Ensure service has an active staff member associated
      service.staff_members << staff_member
      expect(service.staff_members.active).not_to be_empty
      
      result = BookingService.generate_calendar_data(
        service: service,
        date: date,
        tenant: tenant
      )
      
      # Calendar data should contain entries for all days in the month
      start_date = date.beginning_of_month
      end_date = date.end_of_month
      
      expect(result.keys).to include(start_date.to_s)
      expect(result.keys).to include(end_date.to_s)
      expect(result.keys.count).to eq((end_date - start_date).to_i + 1)
    end
    
    it 'returns empty hash if staff member or service is nil' do
      expect(BookingService.generate_calendar_data(service: service, date: nil, tenant: nil)).to eq({})
    end
    
    it 'returns calendar data for explicit date range' do
      # Mock AvailabilityService to return no slots for simplicity
      allow(AvailabilityService).to receive(:available_slots).and_return([])
      service.staff_members << staff_member
      start_date = date.beginning_of_week(:monday)
      end_date   = start_date + 34.days

      result = BookingService.generate_calendar_data(
        service:     service,
        date:        date,
        tenant:      tenant,
        start_date:  start_date,
        end_date:    end_date
      )

      expect(result.keys).to eq((start_date..end_date).map(&:to_s))
      expect(result.keys.count).to eq(35)
    end
  end
  
  describe '.fetch_available_slots' do
    it 'delegates to AvailabilityService' do
      # Expect the call and provide a return value (empty array is fine for delegation check)
      expect(AvailabilityService).to receive(:available_slots).with(
        staff_member, date, service, interval: 30
      ).and_return([]) 
      
      # The actual method call within BookingService iterates through staff_members
      allow(service).to receive(:staff_members).and_return(double('StaffMembers', active: [staff_member]))
      
      BookingService.fetch_available_slots(
        service: service,
        date: date
      )
    end
    
    it 'returns empty array if required params are missing' do
      expect(BookingService.fetch_available_slots(service: nil, date: date)).to eq([])
      expect(BookingService.fetch_available_slots(service: service, date: nil)).to eq([])
    end
  end
  
  describe '.fetch_staff_availability' do
    let!(:staff_member1) { create(:staff_member) }
    let!(:staff_member2) { create(:staff_member) }
    
    before do
      # Associate staff with service
      service.staff_members << staff_member1
      service.staff_members << staff_member2
    end
    
    it 'returns a hash of staff availability' do
      # Mock the AvailabilityService
      slots1 = [{ start_time: Time.current, end_time: Time.current + 1.hour }]
      slots2 = [{ start_time: Time.current + 2.hours, end_time: Time.current + 3.hours }]
      
      allow(AvailabilityService).to receive(:available_slots).with(staff_member1, date, service).and_return(slots1)
      allow(AvailabilityService).to receive(:available_slots).with(staff_member2, date, service).and_return(slots2)
      
      result = BookingService.fetch_staff_availability(
        service: service,
        date: date
      )
      
      expect(result).to include(staff_member1.id => slots1)
      expect(result).to include(staff_member2.id => slots2)
    end
    
    it 'returns empty hash if service is nil' do
      expect(BookingService.fetch_staff_availability(service: nil, date: date)).to eq({})
    end
    
    it 'returns empty hash if date is nil' do
      expect(BookingService.fetch_staff_availability(service: service, date: nil)).to eq({})
    end
  end
  
  describe '.create_booking' do
    it 'delegates to BookingManager' do
      booking_params = { service_id: service.id }
      expect(BookingManager).to receive(:create_booking).with(booking_params, tenant)
      
      BookingService.create_booking(booking_params, tenant)
    end
  end
  
  describe '.update_booking' do
    let(:booking) { create(:booking) }
    
    it 'delegates to BookingManager' do
      booking_params = { status: 'confirmed' }
      expect(BookingManager).to receive(:update_booking).with(booking, booking_params)
      
      BookingService.update_booking(booking, booking_params)
    end
  end
  
  describe '.cancel_booking' do
    let(:booking) { create(:booking) }
    
    it 'delegates to BookingManager' do
      reason = 'Customer cancelled'
      expect(BookingManager).to receive(:cancel_booking).with(booking, reason, true)
      
      BookingService.cancel_booking(booking, reason)
    end
  end
  
  describe '.slot_available?' do
    let(:start_time) { Time.current }
    let(:end_time) { Time.current + 1.hour }
    
    it 'delegates to AvailabilityService' do
      expect(AvailabilityService).to receive(:is_available?).with(
        staff_member: staff_member,
        start_time: start_time,
        end_time: end_time,
        exclude_booking_id: nil
      )
      
      BookingService.slot_available?(
        staff_member: staff_member,
        start_time: start_time,
        end_time: end_time
      )
    end
  end
end 