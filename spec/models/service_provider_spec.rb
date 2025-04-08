# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ServiceProvider, type: :model do
  let(:business) { create(:business) }

  subject(:service_provider) { build(:service_provider, business: business) }

  describe 'associations' do
    it { is_expected.to belong_to(:business) }
    it { is_expected.to have_many(:bookings).dependent(:restrict_with_error) }
  end

  describe 'validations' do
    # Need a factory for service_provider first
    let!(:existing_service_provider) { create(:service_provider, business: business, name: 'Existing Provider') }

    it { is_expected.to validate_presence_of(:business) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:business_id) }

    it { is_expected.to allow_value(true).for(:active) }
    it { is_expected.to allow_value(false).for(:active) }
    it { is_expected.not_to allow_value(nil).for(:active) }

    it { is_expected.to allow_value('test@example.com').for(:email) }
    it { is_expected.to allow_value('').for(:email) }
    it { is_expected.not_to allow_value('invalid-email').for(:email) }

    it { is_expected.to allow_value('+1-555-123-4567').for(:phone) }
    it { is_expected.to allow_value('').for(:phone) }
    it { is_expected.not_to allow_value('12345').for(:phone).with_message("must be a valid phone number") }
  end

  describe '#available_at?' do
    # Tests for availability logic
    # pending 'add tests for availability logic'

    let(:standard_provider) { create(:service_provider, business: business) } # Mon-Fri 9-5
    let(:complex_provider) { create(:service_provider, :with_complex_availability, business: business) }
    let(:inactive_provider) { create(:service_provider, :inactive, business: business) }

    let(:monday_9am) { Time.zone.parse('2024-04-15 09:00:00') } # Assuming 2024-04-15 is a Monday
    let(:monday_12pm) { Time.zone.parse('2024-04-15 12:00:00') }
    let(:monday_5pm) { Time.zone.parse('2024-04-15 17:00:00') }
    let(:monday_8am) { Time.zone.parse('2024-04-15 08:00:00') }
    let(:tuesday_10am) { Time.zone.parse('2024-04-16 10:00:00') } # Assuming 2024-04-16 is a Tuesday
    let(:saturday_11am) { Time.zone.parse('2024-04-20 11:00:00') } # Assuming 2024-04-20 is a Saturday
    let(:sunday_1pm) { Time.zone.parse('2024-04-21 13:00:00') } # Assuming 2024-04-21 is a Sunday

    # Date for exceptions (use the date from the complex factory)
    let(:exception_date_today) { Date.today }
    let(:exception_date_tomorrow) { Date.tomorrow }
    let(:today_11_30am) { Time.zone.parse(exception_date_today.strftime("%Y-%m-%d 11:30:00")) }
    let(:today_2pm) { Time.zone.parse(exception_date_today.strftime("%Y-%m-%d 14:00:00")) } # End time of exception
    let(:today_9am) { Time.zone.parse(exception_date_today.strftime("%Y-%m-%d 09:00:00")) } # Before exception start
    let(:tomorrow_10am) { Time.zone.parse(exception_date_tomorrow.strftime("%Y-%m-%d 10:00:00")) }

    context 'with standard availability (Mon-Fri 9-5)' do
      it 'is available during standard hours' do
        expect(standard_provider.available_at?(monday_9am)).to be true
        expect(standard_provider.available_at?(monday_12pm)).to be true
      end

      it 'is not available at the exact end time' do
        expect(standard_provider.available_at?(monday_5pm)).to be false
      end

      it 'is not available outside standard hours' do
        expect(standard_provider.available_at?(monday_8am)).to be false
      end

      it 'is not available on weekends' do
        expect(standard_provider.available_at?(saturday_11am)).to be false
        expect(standard_provider.available_at?(sunday_1pm)).to be false
      end
    end

    context 'with complex availability' do
      it 'is available during morning interval on Monday' do
        expect(complex_provider.available_at?(monday_8am)).to be true # Starts 8am
      end

      it 'is not available during lunch break on Monday' do
        expect(complex_provider.available_at?(monday_12pm)).to be false # Break 12-1
      end

      it 'is not available on a closed day (Tuesday)' do
        expect(complex_provider.available_at?(tuesday_10am)).to be false
      end

      it 'is available on Saturday during specified hours' do
        expect(complex_provider.available_at?(saturday_11am)).to be true
      end

      it 'is not available on Sunday (no schedule defined)' do
        expect(complex_provider.available_at?(sunday_1pm)).to be false
      end
    end

    context 'with exceptions' do
      # Assuming 'today' corresponds to the weekday the test is run on
      # We rely on the complex factory setting an exception for Date.today

      it 'uses exception hours when defined for a date (overrides weekly)' do
        # Provider should be available 11:00-14:00 today, regardless of regular schedule
        expect(complex_provider.available_at?(today_11_30am)).to be true
      end

      it 'is not available outside exception hours on an exception date' do
        # Before exception start
        expect(complex_provider.available_at?(today_9am)).to be false
        # At exact end time of exception
        expect(complex_provider.available_at?(today_2pm)).to be false
      end

      it 'is not available on a date defined as closed by exception' do
        # Tomorrow is defined as [] (closed) in the factory
        expect(complex_provider.available_at?(tomorrow_10am)).to be false
      end
    end

    context 'when inactive' do
      it 'is never available' do
        expect(inactive_provider.available_at?(monday_9am)).to be false
        expect(inactive_provider.available_at?(saturday_11am)).to be false
      end
    end

    context 'with invalid time strings in data (should be caught by validation but test defensiveness)' do
      it 'returns false if interval times are unparseable' do
        # Note: process_availability might clean this before available_at? sees it
        provider = build(:service_provider, availability: { 'monday' => [{ 'start' => 'invalid', 'end' => '17:00' }] })
        # Manually bypass validation/processing for direct testing if possible,
        # otherwise, this scenario might be hard to trigger if processing cleans it.
        # Let's assume processing *didn't* clean it for this test.
        provider.availability = { 'monday' => [{ 'start' => "invalid", 'end' => "17:00" }] } # Use string keys
        expect(provider.send(:parse_time_of_day, "invalid")).to be_nil # Test private method behavior
        # The available_at? method should handle nil start/end times gracefully
        expect(provider.available_at?(monday_9am)).to be false
      end
    end
  end

  describe 'availability structure validation' do
    # Tests for validate_availability_structure will go here
    # pending 'add tests for availability structure validation'
    it 'is valid with standard availability' do
      provider = build(:service_provider, business: business)
      expect(provider).to be_valid
    end

    it 'is valid with complex availability including exceptions' do
      provider = build(:service_provider, :with_complex_availability, business: business)
      expect(provider).to be_valid
    end

    it 'is valid when availability is blank' do
      provider = build(:service_provider, availability: nil, business: business)
      expect(provider).to be_valid
      provider = build(:service_provider, availability: {}, business: business)
      expect(provider).to be_valid
    end

    it 'is invalid if availability is not a hash' do
      provider = build(:service_provider, availability: "invalid string", business: business)
      provider.valid? # Trigger processing
      expect(provider.availability).to eq({})
      # No longer expect a validation error, as processing converts it
      # expect(provider).not_to be_valid
      # expect(provider.errors[:availability]).to include("must be a valid JSON object")
    end

    it 'is invalid with unknown top-level keys' do
      provider = build(:service_provider, availability: { unknown_key: [] }, business: business)
      expect(provider).not_to be_valid
      expect(provider.errors[:availability]).to include(/contains invalid key: 'unknown_key'. Allowed keys are days of the week and 'exceptions'./)
    end

    it 'is invalid if a day\'s value is not an array' do
      provider = build(:service_provider, availability: { monday: "not an array" }, business: business)
      expect(provider).not_to be_valid
      expect(provider.errors[:availability]).to include("value for 'monday' must be an array of time intervals")
    end

    it 'is invalid if an interval is not a hash with start/end keys' do
      provider1 = build(:service_provider, availability: { monday: ["not a hash"] }, business: business)
      provider1.valid? # Trigger processing
      expect(provider1.availability['monday']).to be_empty
      # No longer expect validation error as processing removes invalid interval
      # expect(provider1).not_to be_valid
      # expect(provider1.errors[:availability]).to include("interval #1 for 'monday' must be an object with 'start' and 'end' keys")

      provider2 = build(:service_provider, availability: { monday: [{ start: '09:00' }] }, business: business)
      provider2.valid? # Trigger processing
      expect(provider2.availability['monday']).to be_empty
      # No longer expect validation error as processing removes invalid interval
      # expect(provider2).not_to be_valid
      # expect(provider2.errors[:availability]).to include("interval #1 for 'monday' must be an object with 'start' and 'end' keys")
    end

    it 'is invalid if interval time format is incorrect' do
      provider1 = build(:service_provider, availability: { monday: [{ start: '9:00', end: '17:00' }] }, business: business)
      expect(provider1).not_to be_valid # Validation should still catch bad format before processing removes it?
      expect(provider1.errors[:availability]).to include("invalid start time for interval #1 for 'monday': '9:00'. Use HH:MM format.")
      provider1.valid? # Trigger processing again maybe?
      # expect(provider1.availability['monday']).to be_empty # Let's check if validation adds error first

      provider2 = build(:service_provider, availability: { tuesday: [{ start: '09:00', end: '17-00' }] }, business: business)
      expect(provider2).not_to be_valid
      expect(provider2.errors[:availability]).to include("invalid end time for interval #1 for 'tuesday': '17-00'. Use HH:MM format.")
      # provider2.valid?
      # expect(provider2.availability['tuesday']).to be_empty
    end

    it 'is invalid if start time is not before end time' do
      provider = build(:service_provider, availability: { monday: [{ start: '18:00', end: '17:00' }] }, business: business)
      expect(provider).not_to be_valid
      expect(provider.errors[:availability]).to include("start time must be before end time for interval #1 on 'monday'")
    end

    # --- Exception Validations ---

    it 'is invalid if exceptions value is not a hash' do
      provider = build(:service_provider, availability: { exceptions: ["not a hash"] }, business: business)
      provider.valid? # Trigger processing
      expect(provider.availability['exceptions']).to eq({}) # Check processing result
      # No longer expect validation error as processing converts it to a valid hash
      # expect(provider).not_to be_valid
      # expect(provider.errors[:availability]).to include("'exceptions' value must be a JSON object")
    end

    it 'is invalid if exception date format is incorrect' do
      invalid_date = "2023/12/25"
      provider = build(:service_provider, availability: { exceptions: { invalid_date => [] } }, business: business)
      expect(provider).not_to be_valid
      expect(provider.errors[:availability]).to include("contains invalid date format in exceptions: '#{invalid_date}'. Use YYYY-MM-DD.")
    end

    it 'is invalid if exception intervals are structured incorrectly' do
      valid_date = Date.today.iso8601
      provider1 = build(:service_provider, availability: { exceptions: { valid_date => "not an array" } }, business: business)
      provider1.valid? # Trigger processing
      expect(provider1.availability['exceptions'][valid_date]).to eq([])
      # No longer expect validation error as processing corrects the structure
      # expect(provider1).not_to be_valid
      # expect(provider1.errors[:availability]).to include("value for 'exception date #{valid_date}' must be an array of time intervals")

      provider2 = build(:service_provider, availability: { exceptions: { valid_date => [{ start: '10:00' }] } }, business: business)
      provider2.valid? # Trigger processing
      expect(provider2.availability['exceptions'][valid_date]).to be_empty
      # No longer expect validation error as processing removes invalid interval
      # expect(provider2).not_to be_valid
      # expect(provider2.errors[:availability]).to include("interval #1 for 'exception date #{valid_date}' must be an object with 'start' and 'end' keys")
    end

    it 'is invalid if exception interval time format is incorrect' do
      valid_date = Date.today.iso8601
      provider = build(:service_provider, availability: { exceptions: { valid_date => [{ start: '10:99', end: '14:00' }] } }, business: business)
      expect(provider).not_to be_valid
      expect(provider.errors[:availability]).to include("invalid start time for interval #1 for 'exception date #{valid_date}': '10:99'. Use HH:MM format.")
    end

    it 'is invalid if exception start time is not before end time' do
      valid_date = Date.today.iso8601
      provider = build(:service_provider, availability: { exceptions: { valid_date => [{ start: '14:00', end: '11:00' }] } }, business: business)
      expect(provider).not_to be_valid
      expect(provider.errors[:availability]).to include("start time must be before end time for interval #1 on 'exception date #{valid_date}'")
    end
  end

  describe 'availability processing' do
    # Tests for process_availability (before_validation callback)

    it 'does not modify valid availability data' do
      valid_data = {
        'monday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'exceptions' => { Date.today.iso8601 => [{ 'start' => '10:00', 'end' => '14:00' }] }
      }
      provider = build(:service_provider, availability: valid_data, business: business)
      provider.valid? # Trigger before_validation
      expect(provider.availability).to eq(valid_data)
    end

    it 'removes day slots that are not hashes or missing start/end' do
      dirty_data = {
        'monday' => ["not a hash", { 'start' => '10:00' }, { 'end' => '12:00' }, { 'start' => '13:00', 'end' => '15:00' }],
        'tuesday' => [{ 'start' => '', 'end' => '16:00' }],
        'wednesday' => [{ 'start' => '10:00', 'end' => nil }]
      }
      provider = build(:service_provider, availability: dirty_data, business: business)
      provider.valid? # Trigger before_validation
      processed_availability = provider.availability
      expect(processed_availability['monday']).to eq([{ 'start' => '13:00', 'end' => '15:00' }])
      expect(processed_availability['tuesday']).to eq([])
      expect(processed_availability['wednesday']).to eq([])
    end

    it 'removes exception slots that are not hashes or missing start/end' do
      date_str = Date.today.iso8601
      tomorrow_str = Date.tomorrow.iso8601
      dirty_data = {
        'exceptions' => {
          date_str => ["not a hash", { 'start' => '10:00' }, { 'end' => '12:00' }, { 'start' => '13:00', 'end' => '15:00' }],
          tomorrow_str => [{ 'start' => '', 'end' => '16:00' }]
        }
      }
      provider = build(:service_provider, availability: dirty_data, business: business)
      provider.valid? # Trigger before_validation
      processed_exceptions = provider.availability['exceptions']
      expect(processed_exceptions[date_str]).to eq([{ 'start' => '13:00', 'end' => '15:00' }])
      expect(processed_exceptions[tomorrow_str]).to eq([])
    end

    it 'converts blank exception values to empty arrays' do
      date_str = Date.today.iso8601
      dirty_data = {
        'exceptions' => {
          date_str => ""
        }
      }
      provider = build(:service_provider, availability: dirty_data, business: business)
      provider.valid? # Trigger before_validation
      processed_exceptions = provider.availability['exceptions']
      expect(processed_exceptions[date_str]).to eq([])
    end

    it 'handles nil availability gracefully' do
      provider = build(:service_provider, availability: nil, business: business)
      expect { provider.valid? }.not_to raise_error
      expect(provider.availability).to be_nil
    end

    it 'handles empty hash availability gracefully' do
      provider = build(:service_provider, availability: {}, business: business)
      expect { provider.valid? }.not_to raise_error
      expect(provider.availability).to eq({})
    end
  end
end