# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BookingPolicy, type: :model do
  let(:business) { create(:business) }
  
  describe 'associations' do
    it { should belong_to(:business) }
  end
  
  describe 'validations' do
    it { should validate_numericality_of(:cancellation_window_mins).is_greater_than_or_equal_to(0).allow_nil }
    it { should validate_numericality_of(:buffer_time_mins).is_greater_than_or_equal_to(0).allow_nil }
    it { should validate_numericality_of(:max_daily_bookings).is_greater_than_or_equal_to(0).allow_nil }
    it { should validate_numericality_of(:max_advance_days).is_greater_than_or_equal_to(0).allow_nil }
    it { should validate_numericality_of(:min_duration_mins).is_greater_than_or_equal_to(0).allow_nil }
    it { should validate_numericality_of(:max_duration_mins).is_greater_than_or_equal_to(0).allow_nil }
    it { should validate_numericality_of(:min_advance_mins).is_greater_than_or_equal_to(0).allow_nil }
  
    context 'custom validations' do
      it 'validates min_duration_mins is not greater than max_duration_mins' do
        policy = build(:booking_policy, business: business, min_duration_mins: 60, max_duration_mins: 30)
        expect(policy).not_to be_valid
        expect(policy.errors[:min_duration_mins]).to include('cannot be greater than maximum duration')
      end
      
      it 'allows min_duration_mins to equal max_duration_mins' do
        policy = build(:booking_policy, business: business, min_duration_mins: 60, max_duration_mins: 60)
        expect(policy).to be_valid
      end
      
      it 'allows min_duration_mins to be less than max_duration_mins' do
        policy = build(:booking_policy, business: business, min_duration_mins: 30, max_duration_mins: 60)
        expect(policy).to be_valid
      end
      
      it 'is valid when only min_duration_mins is set' do
        policy = build(:booking_policy, business: business, min_duration_mins: 30, max_duration_mins: nil)
        expect(policy).to be_valid
      end
      
      it 'is valid when only max_duration_mins is set' do
        policy = build(:booking_policy, business: business, min_duration_mins: nil, max_duration_mins: 60)
        expect(policy).to be_valid
      end
    end
    
    context 'min_advance_mins validations' do
      it 'allows valid minimum advance time values' do
        policy = build(:booking_policy, business: business, min_advance_mins: 30)
        expect(policy).to be_valid
      end
      
      it 'allows zero minimum advance time' do
        policy = build(:booking_policy, business: business, min_advance_mins: 0)
        expect(policy).to be_valid
      end
      
      it 'allows nil minimum advance time' do
        policy = build(:booking_policy, business: business, min_advance_mins: nil)
        expect(policy).to be_valid
      end
      
      it 'rejects negative minimum advance time' do
        policy = build(:booking_policy, business: business, min_advance_mins: -15)
        expect(policy).not_to be_valid
        expect(policy.errors[:min_advance_mins]).to include('must be greater than or equal to 0')
      end
    end

    context 'fixed intervals validations' do
      it 'allows valid fixed intervals when enabled' do
        policy = build(:booking_policy, business: business, use_fixed_intervals: true, interval_mins: 30)
        expect(policy).to be_valid
      end
      
      it 'does not require interval_mins when fixed intervals is disabled' do
        policy = build(:booking_policy, business: business, use_fixed_intervals: false, interval_mins: nil)
        expect(policy).to be_valid
      end
      
      it 'requires interval_mins when fixed intervals is enabled' do
        policy = build(:booking_policy, business: business, use_fixed_intervals: true, interval_mins: nil)
        expect(policy).not_to be_valid
        expect(policy.errors[:interval_mins]).to include('must be present when using fixed intervals')
      end
      
      it 'rejects interval_mins less than 5 minutes' do
        policy = build(:booking_policy, business: business, use_fixed_intervals: true, interval_mins: 3)
        expect(policy).not_to be_valid
        expect(policy.errors[:interval_mins]).to include('must be at least 5 minutes when using fixed intervals')
      end
      
      it 'rejects interval_mins not divisible by 5' do
        policy = build(:booking_policy, business: business, use_fixed_intervals: true, interval_mins: 23)
        expect(policy).not_to be_valid
        expect(policy.errors[:interval_mins]).to include('must be divisible by 5 when using fixed intervals')
      end
      
      it 'accepts valid interval_mins values' do
        [5, 10, 15, 30, 60].each do |interval|
          policy = build(:booking_policy, business: business, use_fixed_intervals: true, interval_mins: interval)
          expect(policy).to be_valid
        end
      end
    end
  end

  describe '#slot_interval_mins' do
    let(:service) { build(:service, duration: 32) }
    
    context 'when use_fixed_intervals is false' do
      let(:policy) { build(:booking_policy, business: business, use_fixed_intervals: false, interval_mins: 30) }
      
      it 'returns the service duration' do
        expect(policy.slot_interval_mins(service)).to eq(32)
      end
      
      it 'returns 30 when service is nil' do
        expect(policy.slot_interval_mins(nil)).to eq(30)
      end
    end
    
    context 'when use_fixed_intervals is true' do
      let(:policy) { build(:booking_policy, business: business, use_fixed_intervals: true, interval_mins: 30) }
      
      it 'returns the interval_mins regardless of service duration' do
        expect(policy.slot_interval_mins(service)).to eq(30)
      end
      
      it 'returns the interval_mins when service is nil' do
        expect(policy.slot_interval_mins(nil)).to eq(30)
      end
    end
  end
end 