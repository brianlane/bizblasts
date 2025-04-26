require 'rails_helper'
require 'tod' # Make sure Tod is available

RSpec.describe AvailabilityService, type: :service do
  # Use let! for tenant so it exists for all contexts
  let!(:business) { create(:business) }
  # Use let (lazy) for service - only created when needed
  let(:service) { create(:service, business: business, duration: 60) }
  let(:date) { Date.new(2024, 5, 15) } # A Wednesday

  # Create staff member within a before block to ensure tenant is set
  let(:staff_member) { create(:staff_member, business: business) }

  # Set tenant context for ALL examples in this describe block
  around do |example|
    ActsAsTenant.with_tenant(business) do
      example.run
    end
  end

  before do
    # Set up availability for the staff member (9 AM to 5 PM weekdays)
    availability = {
      'monday' => [{ 'start' => '09:00', 'end' => '17:00' }],
      'tuesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
      'wednesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
      'thursday' => [{ 'start' => '09:00', 'end' => '17:00' }],
      'friday' => [{ 'start' => '09:00', 'end' => '17:00' }],
      'saturday' => [],
      'sunday' => [],
      'exceptions' => {}
    }
    staff_member.update!(availability: availability)
    
    # Add service to staff member
    create(:services_staff_member, service: service, staff_member: staff_member)
  end

  describe '.available_slots' do
    context 'when the staff member is inactive' do
      before { staff_member.update!(active: false) }

      it 'returns an empty array' do
        slots = described_class.available_slots(staff_member, date, service)
        expect(slots).to be_empty
      end
    end

    context 'when staff member has standard 9-5 availability' do
      let(:standard_availability) do
        {
          monday: [{ "start" => "09:00", "end" => "17:00" }],
          tuesday: [{ "start" => "09:00", "end" => "17:00" }],
          wednesday: [{ "start" => "09:00", "end" => "17:00" }], 
          thursday: [{ "start" => "09:00", "end" => "17:00" }],
          friday: [{ "start" => "09:00", "end" => "17:00" }],
          saturday: [],
          sunday: [],
          exceptions: {}
        }
      end
      
      before do 
        staff_member.update!(availability: standard_availability)
      end

      context 'and no existing bookings' do
        it 'returns all slots within the 9-5 range for a 60min service' do
          slots = described_class.available_slots(staff_member, date, service, interval: 30)
          
          # Expected times: 9:00, 9:30, 10:00, ..., 16:00 (last slot starts at 16:00, ends 17:00)
          expected_start_times = (9..16).flat_map { |h| [sprintf('%02d:%s', h, '00'), sprintf('%02d:%s', h, '30')] }[0..-2]
          expect(slots.count).to eq(expected_start_times.count)

          # Compare formatted time strings
          actual_times = slots.map do |slot|
            {
              start: slot[:start_time].strftime('%H:%M'),
              end: slot[:end_time].strftime('%H:%M')
            }
          end

          # Verify each slot has the correct format and duration
          slots.each do |slot|
            expect(slot).to have_key(:start_time)
            expect(slot).to have_key(:end_time)
            expect(slot[:start_time]).to be_a(Time)
            expect(slot[:end_time]).to be_a(Time)
            expect(slot[:end_time] - slot[:start_time]).to eq(60.minutes) # 60 min service
          end

          # Verify the start times match expected
          actual_start_times = slots.map { |s| s[:start_time].strftime('%H:%M') }
          expect(actual_start_times).to match_array(expected_start_times)
        end

        it 'returns slots for a different interval (e.g., 15 mins)' do
          slots = described_class.available_slots(staff_member, date, service, interval: 15)
          expect(slots).not_to be_empty
          
          # Verify slot format
          slots.each do |slot|
            expect(slot).to have_key(:start_time)
            expect(slot).to have_key(:end_time)
            expect(slot[:start_time]).to be_a(Time)
            expect(slot[:end_time]).to be_a(Time)
          end
        end
      end

      context 'and an existing booking conflicts' do
        let!(:customer) { create(:tenant_customer, business: business) }

        before do
          create(:booking, 
                 business: business,
                 staff_member: staff_member,
                 service: service, 
                 tenant_customer: customer, 
                 start_time: Time.use_zone(Time.zone) { Time.zone.parse("#{date.iso8601} 11:00") },
                 end_time: Time.use_zone(Time.zone) { Time.zone.parse("#{date.iso8601} 12:00") },
                 status: :confirmed)
        end

        it 'excludes slots that overlap with the booking (considering buffer/duration)' do
          slots = described_class.available_slots(staff_member, date, service, interval: 30)
          
          # Map to start times for easier comparison
          slot_times_h_m = slots.map { |slot| slot[:start_time].strftime('%H:%M') }

          expect(slot_times_h_m).not_to include('10:30') # Starts during booking
          expect(slot_times_h_m).not_to include('11:00') # Starts during booking
          expect(slot_times_h_m).not_to include('11:30') # Starts during booking

          expect(slot_times_h_m).to include('09:00')
          expect(slot_times_h_m).to include('09:30')
          expect(slot_times_h_m).to include('10:00') # Should be included
          expect(slot_times_h_m).to include('12:00') # Should be included
          expect(slot_times_h_m).to include('12:30')
          expect(slot_times_h_m).to include('16:00')

          # Verify each slot has correct format
          slots.each do |slot|
            expect(slot).to have_key(:start_time)
            expect(slot).to have_key(:end_time)
            expect(slot[:start_time]).to be_a(Time)
            expect(slot[:end_time]).to be_a(Time)
          end
        end
      end
    end
    
    context 'when staff member has split shift availability' do
      let(:split_availability) do
        {
          monday: [{ "start" => "09:00", "end" => "12:00" }, { "start" => "14:00", "end" => "17:00" }],
          wednesday: [{ "start" => "09:00", "end" => "12:00" }, { "start" => "14:00", "end" => "17:00" }], 
          # Other days omitted for brevity or empty
        }
      end
      before { staff_member.update!(availability: split_availability) }

      it 'returns slots only within the defined intervals' do
        slots = described_class.available_slots(staff_member, date, service, interval: 30)
        slot_times_h_m = slots.map { |slot| slot[:start_time].strftime('%H:%M') }

        # Should include slots in 9-12 and 14-17 ranges
        expect(slot_times_h_m).to include('09:00')
        expect(slot_times_h_m).to include('11:00') # Last start time for 9-12 with 60min duration
        expect(slot_times_h_m).to include('14:00')
        expect(slot_times_h_m).to include('16:00') # Last start time for 14-17

        # Should NOT include slots during the break or outside hours
        expect(slot_times_h_m).not_to include('08:30')
        expect(slot_times_h_m).not_to include('11:30') # End time would be 12:30
        expect(slot_times_h_m).not_to include('12:00')
        expect(slot_times_h_m).not_to include('12:30')
        expect(slot_times_h_m).not_to include('13:00')
        expect(slot_times_h_m).not_to include('13:30')
        expect(slot_times_h_m).not_to include('16:30') # End time would be 17:30
        expect(slot_times_h_m).not_to include('17:00')
      end
    end

    context 'when there is a date exception (holiday)' do
      let(:availability_with_exception) do
        {
          wednesday: [{ "start" => "09:00", "end" => "17:00" }], 
          exceptions: { date.iso8601 => [] } # Closed on this specific Wednesday
        }
      end
      before { staff_member.update!(availability: availability_with_exception) }

      it 'returns no slots for the exception date' do
        slots = described_class.available_slots(staff_member, date, service, interval: 30)
        expect(slots).to be_empty
      end
    end
    
    context 'when there is a date exception (special hours)' do
      let(:availability_with_special_hours) do
        {
          wednesday: [{ "start" => "09:00", "end" => "17:00" }], # Normal Wednesday
          exceptions: { date.iso8601 => [{ "start" => "10:00", "end" => "14:00" }] } # Special hours
        }
      end
      before { staff_member.update!(availability: availability_with_special_hours) }

      it 'returns slots only within the special hours' do
        slots = described_class.available_slots(staff_member, date, service, interval: 30)
        slot_times_h_m = slots.map { |slot| slot[:start_time].strftime('%H:%M') }

        expect(slot_times_h_m).to include('10:00')
        expect(slot_times_h_m).to include('13:00') # Last start for 60min service ending at 14:00

        expect(slot_times_h_m).not_to include('09:00')
        expect(slot_times_h_m).not_to include('09:30')
        expect(slot_times_h_m).not_to include('13:30')
        expect(slot_times_h_m).not_to include('14:00')
      end
    end

    # TODO: Add tests for non-standard availability, exceptions, etc.
  end

  describe '.is_available?' do
    let(:weekday) { Date.new(2023, 6, 1) } # Thursday
    let(:weekend) { Date.new(2023, 6, 3) } # Saturday
    
    it 'returns true for a time within availability' do
      start_time = Time.zone.local(weekday.year, weekday.month, weekday.day, 10, 0)
      end_time = start_time + 1.hour
      
      result = described_class.is_available?(
        staff_member: staff_member,
        start_time: start_time,
        end_time: end_time,
        service: service
      )
      
      expect(result).to be true
    end
    
    it 'returns false for a time outside availability' do
      start_time = Time.zone.local(weekend.year, weekend.month, weekend.day, 10, 0)
      end_time = start_time + 1.hour
      
      result = described_class.is_available?(
        staff_member: staff_member,
        start_time: start_time,
        end_time: end_time,
        service: service
      )
      
      expect(result).to be false
    end
    
    it 'returns false when there is a booking conflict' do
      booking_time = Time.zone.local(weekday.year, weekday.month, weekday.day, 10, 0)
      create(:booking, 
        staff_member: staff_member, 
        service: service,
        start_time: booking_time, 
        end_time: booking_time + 1.hour, 
        business: business
      )
      
      result = described_class.is_available?(
        staff_member: staff_member,
        start_time: booking_time,
        end_time: booking_time + 1.hour,
        service: service
      )
      
      expect(result).to be false
    end
    
    it 'returns false when staff member cannot perform the service' do
      another_service = create(:service, business: business)
      
      start_time = Time.zone.local(weekday.year, weekday.month, weekday.day, 10, 0)
      end_time = start_time + 1.hour
      
      result = described_class.is_available?(
        staff_member: staff_member,
        start_time: start_time,
        end_time: end_time,
        service: another_service
      )
      
      expect(result).to be false
    end
  end
  
  describe '.availability_calendar' do
    let(:start_date) { Date.new(2023, 6, 1) } # Thursday
    let(:end_date) { Date.new(2023, 6, 3) } # Saturday
    
    it 'returns a hash with dates as keys' do
      calendar = described_class.availability_calendar(
        staff_member: staff_member,
        start_date: start_date,
        end_date: end_date,
        service: service
      )
      
      expect(calendar).to be_a(Hash)
      expect(calendar.keys).to contain_exactly(
        start_date.to_s, 
        (start_date + 1.day).to_s, 
        end_date.to_s
      )
    end
    
    it 'returns empty arrays for dates with no availability' do
      calendar = described_class.availability_calendar(
        staff_member: staff_member,
        start_date: start_date,
        end_date: end_date,
        service: service
      )
      
      expect(calendar[end_date.to_s]).to be_empty # Saturday
    end
    
    it 'returns availability slots for dates with availability' do
      calendar = described_class.availability_calendar(
        staff_member: staff_member,
        start_date: start_date,
        end_date: end_date,
        service: service
      )
      
      expect(calendar[start_date.to_s]).not_to be_empty # Thursday
    end
  end
  
  describe '.available_staff_for_service' do
    let(:date) { Date.new(2023, 6, 1) } # Thursday
    let(:start_time) { Time.zone.local(date.year, date.month, date.day, 10, 0) }
    
    it 'returns staff members who can perform the service and are available' do
      result = described_class.available_staff_for_service(
        service: service,
        date: date,
        start_time: start_time
      )
      
      expect(result).to include(staff_member)
    end
    
    it 'filters out staff members who are not available' do
      # Create a booking that conflicts with the start time
      create(:booking, 
        staff_member: staff_member, 
        service: service,
        start_time: start_time, 
        end_time: start_time + 1.hour, 
        business: business
      )
      
      result = described_class.available_staff_for_service(
        service: service,
        date: date,
        start_time: start_time
      )
      
      expect(result).not_to include(staff_member)
    end
    
    it 'filters out staff members who cannot perform the service' do
      another_service = create(:service, business: business)
      
      result = described_class.available_staff_for_service(
        service: another_service,
        date: date,
        start_time: start_time
      )
      
      expect(result).not_to include(staff_member)
    end
  end
end