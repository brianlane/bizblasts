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

      context 'and no existing appointments' do
        it 'returns all slots within the 9-5 range for a 60min service' do
          # Sanity check
          # staff_member.reload # Might not be needed with around block?
          # puts "[DEBUG] Staff availability in test: #{staff_member.availability.inspect}"
          # expect(staff_member.availability[:wednesday].first["start"]).to eq("09:00")

          slots = described_class.available_slots(staff_member, date, service, interval: 30)

          expected_start_times = (9..16).flat_map { |h| ["#{h}:00", "#{h}:30"] }[0..-2] 
          expect(slots.count).to eq(expected_start_times.count)

          expected_timestamps = expected_start_times.map do |time_str|
            Time.zone.parse("#{date.iso8601} #{time_str}")
          end
          slot_start_times = slots.map { |s| s[:start_time] }
          expect(slot_start_times).to match_array(expected_timestamps)

          slots.each do |slot|
             expect(slot[:end_time]).to eq(slot[:start_time] + service.duration.minutes)
          end
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

      context 'and an existing appointment conflicts' do
        let!(:customer) { create(:tenant_customer, business: tenant) }
        let!(:booking) do
          create(:booking, 
                 business: tenant,
                 staff_member: staff_member,
                 service: service, 
                 tenant_customer: customer, 
                 start_time: Time.zone.parse("#{date.iso8601} 11:00"),
                 end_time: Time.zone.parse("#{date.iso8601} 12:00"),
                 status: :confirmed)
        end

        it 'excludes slots that overlap with the booking (considering buffer/duration)' do
          # Sanity check (optional now, but keep for debug if needed)
          # expect(staff_member.available_at?(Time.zone.parse("#{date.iso8601} 09:00"))).to be true
          
          slots = described_class.available_slots(staff_member, date, service, interval: 30)

          slot_times_h_m = slots.map { |s| s[:start_time].strftime('%H:%M') }

          expect(slot_times_h_m).not_to include('10:00')
          expect(slot_times_h_m).not_to include('10:30')
          expect(slot_times_h_m).not_to include('11:00')
          expect(slot_times_h_m).not_to include('11:30')
          expect(slot_times_h_m).not_to include('12:00') 

          expect(slot_times_h_m).to include('09:00')
          expect(slot_times_h_m).to include('12:30') 
          expect(slot_times_h_m).to include('16:00')
        end
      end
    end
    
    # TODO: Add tests for non-standard availability, exceptions, etc.
  end
end 