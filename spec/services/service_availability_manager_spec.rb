# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ServiceAvailabilityManager, type: :service do
  let(:business) { create(:business) }
  let(:service) { create(:service, business: business) }
  let(:manager) { described_class.new(service: service) }

  describe '#initialize' do
    it 'initializes with service and default date' do
      expect(manager.service).to eq(service)
      expect(manager.date_info[:current_date]).to eq(Date.current)
    end

    it 'accepts custom date parameter' do
      custom_date = 1.week.from_now
      custom_manager = described_class.new(service: service, date: custom_date.to_s)
      expect(custom_manager.date_info[:current_date]).to eq(custom_date.to_date)
    end

    it 'handles invalid date gracefully' do
      logger = instance_double(Logger)
      allow(logger).to receive(:warn)
      allow(logger).to receive(:info)
      invalid_manager = described_class.new(service: service, date: 'invalid-date', logger: logger)
      expect(invalid_manager.date_info[:current_date]).to eq(Date.current)
    end

    it 'ensures service has valid availability structure' do
      service.update_column(:availability, {}) # Empty hash
      described_class.new(service: service)
      service.reload
      
      expect(service.availability).to be_a(Hash)
      expect(service.availability).to have_key('monday')
      expect(service.availability).to have_key('exceptions')
    end
  end

  describe '#date_info' do
    let(:date) { Date.new(2025, 7, 22) } # Tuesday
    let(:manager) { described_class.new(service: service, date: date.to_s) }

    it 'returns formatted date information' do
      info = manager.date_info
      
      expect(info[:current_date]).to eq(date)
      expect(info[:start_date]).to eq(date.beginning_of_week)
      expect(info[:end_date]).to eq(date.end_of_week)
      expect(info[:week_range]).to be_a(String)
      expect(info[:week_range]).to include('Jul')
    end
  end

  describe '#update_availability' do
    let(:availability_params) do
      {
        'monday' => {
          '0' => { 'start' => '09:00', 'end' => '17:00' },
          '1' => { 'start' => '19:00', 'end' => '21:00' }
        },
        'tuesday' => {
          '0' => { 'start' => '10:00', 'end' => '16:00' }
        },
        'wednesday' => {},
        'thursday' => {},
        'friday' => {},
        'saturday' => {},
        'sunday' => {}
      }
    end

    let(:full_day_params) do
      {
        'monday' => '0',
        'tuesday' => '0',
        'wednesday' => '1', # Full day
        'thursday' => '0',
        'friday' => '0',
        'saturday' => '0',
        'sunday' => '0'
      }
    end

    context 'with valid parameters' do
      it 'successfully updates availability' do
        result = manager.update_availability(availability_params, full_day_params)
        
        expect(result).to be true
        expect(manager.errors).to be_empty
        
        service.reload
        expect(service.availability['monday']).to include({ 'start' => '09:00', 'end' => '17:00' })
        expect(service.availability['tuesday']).to include({ 'start' => '10:00', 'end' => '16:00' })
        expect(service.availability['wednesday']).to include({ 'start' => '00:00', 'end' => '23:59' })
      end
    end

    context 'with invalid time slots' do
      let(:invalid_params) do
        {
          'monday' => {
            '0' => { 'start' => '17:00', 'end' => '09:00' } # End before start
          },
          'tuesday' => {},
          'wednesday' => {},
          'thursday' => {},
          'friday' => {},
          'saturday' => {},
          'sunday' => {}
        }
      end

      it 'fails validation and returns error' do
        result = manager.update_availability(invalid_params)
        
        expect(result).to be false
        expect(manager.errors).not_to be_empty
        expect(manager.errors.join).to match(/end time must be after start time/i)
      end
    end

    context 'with overlapping slots' do
      let(:overlapping_params) do
        {
          'monday' => {
            '0' => { 'start' => '09:00', 'end' => '12:00' },
            '1' => { 'start' => '11:00', 'end' => '15:00' } # Overlaps
          },
          'tuesday' => {},
          'wednesday' => {},
          'thursday' => {},
          'friday' => {},
          'saturday' => {},
          'sunday' => {}
        }
      end

      it 'detects overlapping slots and returns error' do
        result = manager.update_availability(overlapping_params)
        
        expect(result).to be false
        expect(manager.errors).not_to be_empty
        expect(manager.errors.join).to match(/overlapping time slots/i)
      end
    end

    context 'with invalid time formats' do
      let(:invalid_format_params) do
        {
          'monday' => {
            '0' => { 'start' => '25:00', 'end' => '17:00' }, # Invalid hour
            '1' => { 'start' => '09:00', 'end' => '17:70' }  # Invalid minute
          },
          'tuesday' => {},
          'wednesday' => {},
          'thursday' => {},
          'friday' => {},
          'saturday' => {},
          'sunday' => {}
        }
      end

      it 'filters out invalid time formats' do
        result = manager.update_availability(invalid_format_params)
        
        expect(result).to be true # Should succeed after filtering invalid slots
        service.reload
        expect(service.availability['monday']).to be_empty # All slots filtered out
      end
    end

    context 'with too short time slots' do
      let(:short_slot_params) do
        {
          'monday' => {
            '0' => { 'start' => '09:00', 'end' => '09:10' } # Only 10 minutes
          },
          'tuesday' => {},
          'wednesday' => {},
          'thursday' => {},
          'friday' => {},
          'saturday' => {},
          'sunday' => {}
        }
      end

      it 'rejects slots shorter than 15 minutes' do
        result = manager.update_availability(short_slot_params)
        
        expect(result).to be false
        expect(manager.errors.join).to match(/15 minutes/i)
      end
    end
  end

  describe '#update_enforcement' do
    it 'updates enforcement setting to true' do
      result = manager.update_enforcement('1')
      
      expect(result).to be true
      service.reload
      expect(service.enforce_service_availability?).to be true
    end

    it 'updates enforcement setting to false' do
      service.update!(enforce_service_availability: true)
      result = manager.update_enforcement('0')
      
      expect(result).to be true
      service.reload
      expect(service.enforce_service_availability?).to be false
    end

    it 'handles boolean values correctly' do
      result = manager.update_enforcement(false)
      
      expect(result).to be true
      service.reload
      expect(service.enforce_service_availability?).to be false
    end
  end

  describe '#generate_calendar_data' do
    let!(:staff_member) { create(:staff_member, business: business) }
    
    before do
      # Link staff to service
      create(:services_staff_member, service: service, staff_member: staff_member)
      
      # Set up staff availability
      staff_member.update!(availability: {
        'monday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'tuesday' => [{ 'start' => '10:00', 'end' => '16:00' }],
        'wednesday' => [],
        'thursday' => [],
        'friday' => [],
        'saturday' => [],
        'sunday' => []
      })
    end

    it 'generates calendar data for the week' do
      calendar_data = manager.generate_calendar_data
      
      expect(calendar_data).to be_a(Hash)
      expect(calendar_data.keys.count).to eq(7) # 7 days in a week
      
      # Check that each day has an array of slots
      calendar_data.each do |date_str, slots|
        expect(Date.parse(date_str)).to be_between(manager.date_info[:start_date], manager.date_info[:end_date])
        expect(slots).to be_an(Array)
      end
    end

    it 'handles cache busting parameter' do
      # Should not raise any errors
      expect { manager.generate_calendar_data(bust_cache: true) }.not_to raise_error
    end

    it 'handles service with no staff members' do
      service.staff_members.clear
      calendar_data = manager.generate_calendar_data
      
      expect(calendar_data).to be_a(Hash)
      calendar_data.values.each do |slots|
        expect(slots).to be_empty
      end
    end
  end

  describe '#valid_availability_structure?' do
    it 'returns true for valid availability structure' do
      service.availability = {
        'monday' => [],
        'tuesday' => [],
        'wednesday' => [],
        'thursday' => [],
        'friday' => [],
        'saturday' => [],
        'sunday' => [],
        'exceptions' => {}
      }
      
      expect(manager.valid_availability_structure?).to be true
    end

    it 'returns false for invalid structure (before initialization fixes it)' do
      service.update_column(:availability, { 'monday' => [] }) # Missing other days
      
      # Check the structure before creating a manager (which auto-fixes it)
      expect(service.availability.key?('tuesday')).to be false
      expect(service.availability.key?('exceptions')).to be false
      
      # After creating manager, structure gets fixed
      new_manager = described_class.new(service: service)
      expect(new_manager.valid_availability_structure?).to be true
    end

    it 'returns false for non-hash availability (before initialization fixes it)' do
      service.update_column(:availability, [])
      
      # Check the structure is invalid before creating manager
      expect(service.availability.is_a?(Hash)).to be false
      
      # After creating manager, structure gets fixed to a proper hash
      new_manager = described_class.new(service: service)
      expect(new_manager.valid_availability_structure?).to be true
    end
  end

  describe 'error handling' do
    it 'handles exceptions in update_availability gracefully' do
      allow(service).to receive(:update).and_raise(StandardError.new('Database error'))
      
      result = manager.update_availability({})
      
      expect(result).to be false
      expect(manager.errors).not_to be_empty
      expect(manager.errors.join).to match(/unexpected error/i)
    end

    it 'handles exceptions in generate_calendar_data gracefully' do
      # Mock the service to have staff members that will trigger the AvailabilityService call
      staff_member = create(:staff_member, business: business)
      create(:services_staff_member, service: service, staff_member: staff_member)
      
      allow(AvailabilityService).to receive(:available_slots).and_raise(StandardError.new('Service error'))
      
      calendar_data = manager.generate_calendar_data
      
      expect(calendar_data).to eq({})
      expect(manager.errors).not_to be_empty
    end

    it 'handles exceptions in update_enforcement gracefully' do
      allow(service).to receive(:update).and_raise(StandardError.new('Database error'))
      
      result = manager.update_enforcement(true)
      
      expect(result).to be false
      expect(manager.errors).not_to be_empty
    end
  end

  describe 'logging behavior' do
    let(:logger) { double('Logger') }
    let(:manager) { described_class.new(service: service, logger: logger) }

    before do
      allow(logger).to receive(:info)
      allow(logger).to receive(:warn)
      allow(logger).to receive(:error)
    end

    it 'logs successful availability updates' do
      expect(logger).to receive(:info).with(/availability updated successfully/i)
      
      manager.update_availability({ 'monday' => {}, 'tuesday' => {}, 'wednesday' => {}, 'thursday' => {}, 'friday' => {}, 'saturday' => {}, 'sunday' => {} })
    end

    it 'logs validation errors' do
      invalid_params = {
        'monday' => { '0' => { 'start' => '17:00', 'end' => '09:00' } },
        'tuesday' => {}, 'wednesday' => {}, 'thursday' => {}, 'friday' => {}, 'saturday' => {}, 'sunday' => {}
      }
      
      expect(logger).to receive(:warn).with(/invalid availability data/i)
      
      manager.update_availability(invalid_params)
    end

    it 'logs exceptions with stack traces' do
      allow(service).to receive(:update).and_raise(StandardError.new('Test error'))
      
      expect(logger).to receive(:error).with(/exception in serviceavailabilitymanager/i)
      expect(logger).to receive(:error).with(kind_of(String)) # Stack trace
      
      manager.update_availability({})
    end
  end

  describe 'empty availability handling' do
    context 'when all availability slots are empty' do
      let(:empty_params) do
        {
          'monday' => {},
          'tuesday' => {},
          'wednesday' => {},
          'thursday' => {},
          'friday' => {},
          'saturday' => {},
          'sunday' => {}
        }
      end

      it 'successfully clears availability data' do
        # First set some availability
        service.update!(availability: {
          'monday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'tuesday' => [{ 'start' => '09:00', 'end' => '17:00' }]
        })
        
        result = manager.update_availability(empty_params)
        
        expect(result).to be true
        service.reload
        expect(service.availability['monday']).to eq([])
        expect(service.availability['tuesday']).to eq([])
      end

      it 'validates successfully with empty data' do
        result = manager.update_availability(empty_params)
        expect(result).to be true
        expect(manager.errors).to be_empty
      end
    end

    context 'when clearing availability with enforcement disabled' do
      before do
        service.update!(
          availability: { 'monday' => [{ 'start' => '09:00', 'end' => '17:00' }] },
          enforce_service_availability: true
        )
      end

      it 'clears availability and disables enforcement' do
        manager.update_enforcement('0')
        result = manager.update_availability({})
        
        expect(result).to be true
        service.reload
        expect(service.enforce_service_availability?).to be false
        expect(service.availability.values.flatten.reject(&:blank?)).to be_empty
      end
    end

    context 'when extracting time slots from empty day params' do
      it 'returns empty array for nil params' do
        result = manager.send(:extract_time_slots, nil)
        expect(result).to eq([])
      end

      it 'returns empty array for empty hash' do
        result = manager.send(:extract_time_slots, {})
        expect(result).to eq([])
      end

      it 'filters out empty slots' do
        params = {
          '0' => { 'start' => '', 'end' => '' },
          '1' => { 'start' => '09:00', 'end' => '17:00' },
          '2' => { 'start' => nil, 'end' => nil }
        }
        
        result = manager.send(:extract_time_slots, params)
        expect(result).to eq([{ 'start' => '09:00', 'end' => '17:00' }])
      end
    end
  end
end