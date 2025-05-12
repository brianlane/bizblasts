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
  end
end 