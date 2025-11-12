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
        expect(policy.errors[:interval_mins]).to include('is not a number')
      end
      
      it 'rejects interval_mins less than 5 minutes' do
        policy = build(:booking_policy, business: business, use_fixed_intervals: true, interval_mins: 3)
        expect(policy).not_to be_valid
        expect(policy.errors[:interval_mins]).to include('must be greater than or equal to 5')
      end
      
      it 'rejects interval_mins not divisible by 5' do
        policy = build(:booking_policy, business: business, use_fixed_intervals: true, interval_mins: 23)
        expect(policy).not_to be_valid
        expect(policy.errors[:interval_mins]).to include('must be divisible by 5 when using fixed intervals')
      end
      
      it 'accepts valid interval_mins values' do
        [5, 10, 15, 30, 60, 120].each do |interval|
          policy = build(:booking_policy, business: business, use_fixed_intervals: true, interval_mins: interval)
          expect(policy).to be_valid
        end
      end
      
      it 'rejects interval_mins greater than 120 minutes' do
        policy = build(:booking_policy, business: business, use_fixed_intervals: true, interval_mins: 150)
        expect(policy).not_to be_valid
        expect(policy.errors[:interval_mins]).to include('must be less than or equal to 120')
      end
    end
  end

  describe '#slot_interval_mins' do
    let(:service) { build(:service, duration: 32) }

    context 'when use_fixed_intervals is false' do
      let(:policy) { build(:booking_policy, business: business, use_fixed_intervals: false, interval_mins: 30) }

      it 'returns nil to let calling code use default logic' do
        expect(policy.slot_interval_mins(service)).to be_nil
      end

      it 'returns nil when service is nil' do
        expect(policy.slot_interval_mins(nil)).to be_nil
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

  describe '#service_radius_active?' do
    context 'when service radius is fully configured' do
      it 'returns true when enabled with explicit radius' do
        policy = build(:booking_policy, business: business,
                      service_radius_enabled: true,
                      service_radius_miles: 25)
        expect(policy.service_radius_active?).to be true
      end

      it 'returns true when enabled without explicit radius (uses default)' do
        policy = build(:booking_policy, business: business,
                      service_radius_enabled: true,
                      service_radius_miles: nil)
        expect(policy.service_radius_active?).to be true
      end
    end

    context 'when service radius is not fully configured' do
      it 'returns false when disabled even with radius set' do
        policy = build(:booking_policy, business: business,
                      service_radius_enabled: false,
                      service_radius_miles: 25)
        expect(policy.service_radius_active?).to be false
      end

      it 'returns false when disabled and no radius' do
        policy = build(:booking_policy, business: business,
                      service_radius_enabled: false,
                      service_radius_miles: nil)
        expect(policy.service_radius_active?).to be false
      end
    end

    context 'edge cases' do
      it 'returns true for zero radius (though validation prevents saving this)' do
        policy = build(:booking_policy, business: business,
                      service_radius_enabled: true,
                      service_radius_miles: 0)
        # Zero is present (not nil/blank), so service_radius_active? returns true
        # However, validation will prevent this from being saved (must be > 0)
        expect(policy.service_radius_active?).to be true
        expect(policy.effective_service_radius_miles).to eq(0)
        expect(policy).not_to be_valid # Validation catches this
        expect(policy.errors[:service_radius_miles]).to include('must be greater than 0 when service radius is enabled')
      end

      it 'returns nil (falsy) when enabled is nil' do
        policy = build(:booking_policy, business: business,
                      service_radius_enabled: nil,
                      service_radius_miles: 25)
        # When the boolean column is nil, the && operator returns nil (not false)
        expect(policy.service_radius_active?).to be_nil
        expect(policy.service_radius_active?).to be_falsy
      end
    end
  end

  describe '#effective_service_radius_miles' do
    context 'when service radius is enabled' do
      it 'returns the configured radius' do
        policy = build(:booking_policy, business: business,
                      service_radius_enabled: true,
                      service_radius_miles: 25)
        expect(policy.effective_service_radius_miles).to eq(25)
      end

      it 'returns default of 50 when radius is nil' do
        policy = build(:booking_policy, business: business,
                      service_radius_enabled: true,
                      service_radius_miles: nil)
        expect(policy.effective_service_radius_miles).to eq(50)
      end

      it 'converts string radius to integer' do
        policy = build(:booking_policy, business: business,
                      service_radius_enabled: true,
                      service_radius_miles: "30")
        expect(policy.effective_service_radius_miles).to eq(30)
      end
    end

    context 'when service radius is disabled' do
      it 'returns nil' do
        policy = build(:booking_policy, business: business,
                      service_radius_enabled: false,
                      service_radius_miles: 25)
        expect(policy.effective_service_radius_miles).to be_nil
      end
    end
  end

  describe 'method naming to avoid ActiveRecord conflicts' do
    it 'preserves access to the auto-generated service_radius_enabled boolean column predicate' do
      policy = build(:booking_policy, business: business,
                    service_radius_enabled: true,
                    service_radius_miles: 25)

      # Direct boolean column access (auto-generated by ActiveRecord)
      expect(policy.service_radius_enabled).to be true

      # Custom method that checks both enabled AND configured
      expect(policy.service_radius_active?).to be true
    end

    it 'distinguishes between enabled (column) and active (configured)' do
      policy = build(:booking_policy, business: business,
                    service_radius_enabled: true,
                    service_radius_miles: nil)

      # Column is enabled
      expect(policy.service_radius_enabled).to be true

      # But feature is active (uses default radius)
      expect(policy.service_radius_active?).to be true
    end
  end
end 