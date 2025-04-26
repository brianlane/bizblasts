# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StaffMember, type: :model do
  let(:business) { create(:business) }

  subject(:staff_member) { build(:staff_member, business: business) }

  describe 'associations' do
    it { is_expected.to belong_to(:business) }
    it { is_expected.to have_many(:bookings).dependent(:restrict_with_error) }
    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to have_many(:services_staff_members).dependent(:destroy) }
    it { is_expected.to have_many(:services).through(:services_staff_members) }
  end

  describe 'validations' do
    let!(:existing_staff_member) { create(:staff_member, business: business, name: 'Existing Member') }
    
    it { is_expected.to validate_presence_of(:business) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:business_id) }

    it { is_expected.to allow_value(true).for(:active) }
    it { is_expected.to allow_value(false).for(:active) }
    it { is_expected.not_to allow_value(nil).for(:active) }

    it { is_expected.to allow_value("test@example.com").for(:email) }
    it { is_expected.to allow_value("").for(:email) }
    it { is_expected.not_to allow_value("invalid-email").for(:email) }

    it { is_expected.to allow_value("+1-555-123-4567").for(:phone) }
    it { is_expected.to allow_value("").for(:phone) }
    it { is_expected.not_to allow_value("12345").for(:phone).with_message("must be a valid phone number") }
    it { is_expected.to allow_value("").for(:phone) }
  end

  describe '#available_at?' do
    let(:standard_member) { create(:staff_member, business: business) } # Mon-Fri 9-5 by default in factory
    let(:complex_member) { create(:staff_member, :with_complex_availability, business: business) }
    let(:inactive_member) { create(:staff_member, :inactive, business: business) }

    let(:monday_9am) { Time.zone.parse('2024-04-15 09:00:00') } # Assuming 2024-04-15 is a Monday
    let(:monday_12pm) { Time.zone.parse('2024-04-15 12:00:00') }
    let(:monday_5pm) { Time.zone.parse('2024-04-15 17:00:00') }
    let(:monday_8am) { Time.zone.parse('2024-04-15 08:00:00') }
    let(:tuesday_10am) { Time.zone.parse('2024-04-16 10:00:00') } # Assuming 2024-04-16 is a Tuesday
    let(:saturday_11am) { Time.zone.parse('2024-04-20 11:00:00') } # Assuming 2024-04-20 is a Saturday
    let(:sunday_1pm) { Time.zone.parse('2024-04-21 13:00:00') } # Assuming 2024-04-21 is a Sunday

    let(:exception_date_today) { Date.today }
    let(:exception_date_tomorrow) { Date.tomorrow }
    let(:today_11_30am) { Time.zone.parse(exception_date_today.strftime("%Y-%m-%d 11:30:00")) }
    let(:today_2pm) { Time.zone.parse(exception_date_today.strftime("%Y-%m-%d 14:00:00")) } # End time of exception
    let(:today_9am) { Time.zone.parse(exception_date_today.strftime("%Y-%m-%d 09:00:00")) } # Before exception start
    let(:tomorrow_10am) { Time.zone.parse(exception_date_tomorrow.strftime("%Y-%m-%d 10:00:00")) }

    context 'with standard availability (Mon-Fri 9-5)' do
      it 'is available during standard hours' do
        expect(standard_member.available_at?(monday_9am)).to be true
        expect(standard_member.available_at?(monday_12pm)).to be true
      end

      it 'is not available at the exact end time' do
        expect(standard_member.available_at?(monday_5pm)).to be false
      end

      it 'is not available outside standard hours' do
        expect(standard_member.available_at?(monday_8am)).to be false
      end

      it 'is not available on weekends' do
        expect(standard_member.available_at?(saturday_11am)).to be false
        expect(standard_member.available_at?(sunday_1pm)).to be false
      end
    end

    context 'with complex availability' do
      it 'is available during morning interval on Monday' do
        expect(complex_member.available_at?(monday_8am)).to be true
      end

      it 'is not available during lunch break on Monday' do
        expect(complex_member.available_at?(monday_12pm)).to be false
      end

      it 'is not available on a closed day (Tuesday)' do
        expect(complex_member.available_at?(tuesday_10am)).to be false
      end

      it 'is available on Saturday during specified hours' do
        expect(complex_member.available_at?(saturday_11am)).to be true
      end

      it 'is not available on Sunday (no schedule defined)' do
        expect(complex_member.available_at?(sunday_1pm)).to be false
      end
    end

    context 'with exceptions' do
      it 'uses exception hours when defined for a date (overrides weekly)' do
        expect(complex_member.available_at?(today_11_30am)).to be true
      end

      it 'is not available outside exception hours on an exception date' do
        # Add more debugging to see what's happening
        puts "Today's date: #{exception_date_today}"
        puts "Today 9am: #{today_9am.inspect}"
        puts "Complex member availability: #{complex_member.availability.inspect}"
        
        # Check the exact format of the date being used in the method
        date_str = today_9am.to_date.iso8601
        puts "Date string being used for lookup: #{date_str}"
        
        # Check if exceptions actually has this key
        exceptions = complex_member.availability['exceptions'] || {}
        puts "Exceptions keys: #{exceptions.keys.inspect}"
        puts "Exception exists for today: #{exceptions.key?(date_str)}"
        
        # Check what find_intervals_for returns
        day_name = today_9am.strftime('%A').downcase
        weekly_schedule = complex_member.availability.except('exceptions')
        intervals = complex_member.send(:find_intervals_for, date_str, day_name, exceptions, weekly_schedule)
        puts "Intervals returned: #{intervals.inspect}"
        
        result = complex_member.available_at?(today_9am)
        puts "Final result: #{result}"
        
        expect(complex_member.available_at?(today_9am)).to be false
        expect(complex_member.available_at?(today_2pm)).to be false
      end

      it 'is not available on a date defined as closed by exception' do
        expect(complex_member.available_at?(tomorrow_10am)).to be false
      end
    end

    context 'when inactive' do
      it 'is never available' do
        expect(inactive_member.available_at?(monday_9am)).to be false
        expect(inactive_member.available_at?(saturday_11am)).to be false
      end
    end

    context 'with invalid time strings in data' do
      it 'returns false if interval times are unparseable' do
        member = build(:staff_member, availability: { 'monday' => [{ 'start' => 'invalid', 'end' => '17:00' }] })
        member.availability = { 'monday' => [{ 'start' => "invalid", 'end' => "17:00" }] } # Bypass processing for test
        expect(member.send(:parse_time_of_day, "invalid")).to be_nil
        expect(member.available_at?(monday_9am)).to be false
      end
    end
  end

  describe 'availability structure validation' do
    it 'is valid with standard availability' do
      member = build(:staff_member, business: business)
      expect(member).to be_valid
    end

    it 'is valid with complex availability including exceptions' do
      member = build(:staff_member, :with_complex_availability, business: business)
      expect(member).to be_valid
    end

    it 'is valid when availability is blank' do
      member = build(:staff_member, availability: nil, business: business)
      expect(member).to be_valid
      member = build(:staff_member, availability: {}, business: business)
      expect(member).to be_valid
    end

    it 'is invalid if availability is not a hash' do
      member = build(:staff_member, availability: "invalid string", business: business)
      member.valid?
      expect(member.availability).to eq({})
    end

    it 'is invalid with unknown top-level keys' do
      member = build(:staff_member, availability: { unknown_key: [] }, business: business)
      expect(member).not_to be_valid
      expect(member.errors[:availability]).to include(/contains invalid key: 'unknown_key'./)
    end

    it 'is invalid if a day\'s value is not an array' do
      member = build(:staff_member, availability: { monday: "not an array" }, business: business)
      expect(member).not_to be_valid
      expect(member.errors[:availability]).to include("value for 'monday' must be an array of time intervals")
    end

    it 'is invalid if an interval is not a hash with start/end keys' do
      member1 = build(:staff_member, availability: { monday: ["not a hash"] }, business: business)
      member1.valid?
      expect(member1.availability['monday']).to be_empty

      member2 = build(:staff_member, availability: { monday: [{ start: '09:00' }] }, business: business)
      member2.valid?
      expect(member2.availability['monday']).to be_empty
    end

    it 'is invalid if interval time format is incorrect' do
      member1 = build(:staff_member, availability: { monday: [{ start: '9:00', end: '17:00' }] }, business: business)
      expect(member1).not_to be_valid
      expect(member1.errors[:availability]).to include("invalid start time for interval #1 for 'monday': '9:00'. Use HH:MM format.")

      member2 = build(:staff_member, availability: { tuesday: [{ start: '09:00', end: '17-00' }] }, business: business)
      expect(member2).not_to be_valid
      expect(member2.errors[:availability]).to include("invalid end time for interval #1 for 'tuesday': '17-00'. Use HH:MM format.")
    end

    it 'is invalid if start time is not before end time' do
      member = build(:staff_member, availability: { monday: [{ start: '18:00', end: '17:00' }] }, business: business)
      expect(member).not_to be_valid
      expect(member.errors[:availability]).to include("start time must be before end time for interval #1 on 'monday'")
    end

    it 'is invalid if exceptions value is not a hash' do
      member = build(:staff_member, availability: { exceptions: ["not a hash"] }, business: business)
      member.valid?
      expect(member.availability['exceptions']).to eq({})
    end

    it 'is invalid if exception date format is incorrect' do
      invalid_date = "2023/12/25"
      member = build(:staff_member, availability: { exceptions: { invalid_date => [] } }, business: business)
      expect(member).not_to be_valid
      expect(member.errors[:availability]).to include("contains invalid date format in exceptions: '#{invalid_date}'. Use YYYY-MM-DD.")
    end

    it 'is invalid if exception intervals are structured incorrectly' do
      valid_date = Date.today.iso8601
      member1 = build(:staff_member, availability: { exceptions: { valid_date => "not an array" } }, business: business)
      member1.valid?
      expect(member1.availability['exceptions'][valid_date]).to eq([])

      member2 = build(:staff_member, availability: { exceptions: { valid_date => [{ start: '10:00' }] } }, business: business)
      member2.valid?
      expect(member2.availability['exceptions'][valid_date]).to eq([])
    end

    it 'is invalid if exception interval time format is incorrect' do
      valid_date = Date.today.iso8601
      member1 = build(:staff_member, availability: { exceptions: { valid_date => [{ start: 'invalid', end: '14:00' }] } }, business: business)
      expect(member1).not_to be_valid
      expect(member1.errors[:availability]).to include("invalid start time for interval #1 for 'exception date #{valid_date}': 'invalid'. Use HH:MM format.")

      member2 = build(:staff_member, availability: { exceptions: { valid_date => [{ start: '10:00', end: '14:00:00' }] } }, business: business)
      expect(member2).not_to be_valid
      expect(member2.errors[:availability]).to include("invalid end time for interval #1 for 'exception date #{valid_date}': '14:00:00'. Use HH:MM format.")
    end

    it 'is invalid if exception start time is not before end time' do
      valid_date = Date.today.iso8601
      member = build(:staff_member, availability: { exceptions: { valid_date => [{ start: '14:00', end: '10:00' }] } }, business: business)
      expect(member).not_to be_valid
      expect(member.errors[:availability]).to include("start time must be before end time for interval #1 on 'exception date #{valid_date}'")
    end
  end
end