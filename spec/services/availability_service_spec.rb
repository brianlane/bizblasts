require 'rails_helper'
require 'tod' # Make sure Tod is available

RSpec.describe AvailabilityService, type: :service do
  # Use let! for tenant so it exists for all contexts
  let!(:tenant) { create(:business) }
  # Use let (lazy) for service - only created when needed
  let(:service) { create(:service, business: tenant, duration: 60) }
  let(:date) { Date.new(2024, 5, 15) } # A Wednesday

  # Create staff member within a before block to ensure tenant is set
  let(:staff_member) { create(:staff_member, business: tenant) }

  # Set tenant context for ALL examples in this describe block
  around do |example|
    ActsAsTenant.with_tenant(tenant) do
      example.run
    end
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
      # Define availability hash using let
      let(:standard_availability) do
        {
          # Use symbols for days, strings for interval keys
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
      
      # Apply availability in a before block within this context
      before do 
        staff_member.update!(availability: standard_availability)
      end

      context 'and no existing bookings' do
        it 'returns all slots within the 9-5 range for a 60min service' do
          slots = described_class.available_slots(staff_member, date, service, interval: 30)
          # Expected times: 9:00, 9:30, 10:00, ..., 16:00 (last slot starts at 16:00, ends 17:00)
          expected_start_times = (9..16).flat_map { |h| [sprintf('%02d:%s', h, '00'), sprintf('%02d:%s', h, '30')] }[0..-2]
          expect(slots.count).to eq(expected_start_times.count)

          # Compare formatted time strings instead of full Time objects
          actual_time_strings = slots.map { |t| t.strftime('%H:%M') }
          expect(actual_time_strings).to match_array(expected_start_times)

          # Cannot check end_time directly anymore as slots are just start times
          # expect(slots).to all(be_a(Time)) # Optional: verify type
        end

        it 'returns slots for a different interval (e.g., 15 mins)' do
           # Sanity check
           # staff_member.reload
           # puts "[DEBUG] Staff availability in test (15min): #{staff_member.availability.inspect}"
           # expect(staff_member.availability[:wednesday].first["start"]).to eq("09:00") 
           
           slots = described_class.available_slots(staff_member, date, service, interval: 15)
           expect(slots).not_to be_empty 
         end
      end

      context 'and an existing booking conflicts' do
        let!(:customer) { create(:tenant_customer, business: tenant) }
        # Remove let! for booking
        # let!(:booking) do ... end

        before do
          # Create booking explicitly before the example runs
          create(:booking, 
                 business: tenant,
                 staff_member: staff_member,
                 service: service, 
                 tenant_customer: customer, 
                 start_time: Time.use_zone(Time.zone) { Time.zone.parse("#{date.iso8601} 11:00") },
                 end_time: Time.use_zone(Time.zone) { Time.zone.parse("#{date.iso8601} 12:00") },
                 status: :confirmed)
        end

        it 'excludes slots that overlap with the booking (considering buffer/duration)' do
          # pending("Investigate persistent failure in filtering overlapping slots") # Un-pending the test

          # === TEST DEBUGGING START === - REMOVED
          # conflicting_booking = Booking.last
          # puts "\n[TEST DEBUG] ..."
          # === TEST DEBUGGING END === - REMOVED
          
          slots = described_class.available_slots(staff_member, date, service, interval: 30)

          # === TEST DEBUGGING START === - REMOVED
          slot_times_h_m = slots.map { |time| time.strftime('%H:%M') }
          # puts "[TEST DEBUG] ..."
          # === TEST DEBUGGING END === - REMOVED

          # A 10:00 booking ends at 11:00, which doesn't overlap with 11:00-12:00 booking.
          # expect(slot_times_h_m).not_to include('10:00') # Incorrect expectation
          expect(slot_times_h_m).not_to include('10:30') # Starts during booking
          expect(slot_times_h_m).not_to include('11:00') # Starts during booking
          expect(slot_times_h_m).not_to include('11:30') # Starts during booking
          # expect(slot_times_h_m).not_to include('12:00') # Incorrect: Starts exactly when booking ends

          expect(slot_times_h_m).to include('09:00')
          expect(slot_times_h_m).to include('09:30')
          expect(slot_times_h_m).to include('10:00') # Should be included
          expect(slot_times_h_m).to include('12:00') # Should be included
          expect(slot_times_h_m).to include('12:30')
          expect(slot_times_h_m).to include('16:00')
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
        slot_times_h_m = slots.map { |time| time.strftime('%H:%M') }

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
        # Expect an array of Time objects, map them directly
        slot_times_h_m = slots.map { |time| time.strftime('%H:%M') }

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
end 