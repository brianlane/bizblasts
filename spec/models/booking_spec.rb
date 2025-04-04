require 'rails_helper'

RSpec.describe Booking, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:business) }
    it { is_expected.to belong_to(:service) }
    it { is_expected.to belong_to(:staff_member) }
    it { is_expected.to belong_to(:tenant_customer) }
  end

  describe 'validations' do
    # Ensure the base subject is valid by default
    let(:business) { create(:business) }
    let(:staff_member) { create(:staff_member, business: business) }
    let(:tenant_customer) { create(:tenant_customer, business: business) }
    let(:service) { create(:service, business: business) }
    let(:valid_start_time) { Time.zone.parse('2024-10-21 10:00:00') } # Time when provider is available

    subject do
      build(:booking, 
            business: business, 
            staff_member: staff_member, 
            tenant_customer: tenant_customer, 
            service: service,
            start_time: valid_start_time, 
            end_time: valid_start_time + service.duration.minutes)
    end

    it { is_expected.to validate_presence_of(:start_time) }
    it { is_expected.to validate_presence_of(:end_time) }
    it { is_expected.to validate_presence_of(:status) }

    # Custom validation test for end_time after start_time
    it 'is invalid if end_time is before start_time' do
      booking = build(:booking, start_time: Time.current, end_time: Time.current - 1.hour)
      expect(booking).not_to be_valid
      expect(booking.errors[:end_time]).to include("must be after the start time") if booking.errors[:end_time].present?
    end

    it 'is valid if end_time is after start_time' do
      # Ensure the staff member is available at the chosen start time for this specific test
      start_time = Time.zone.parse('2024-10-21 10:00:00') # A time provider is known to be available
      booking = build(:booking, staff_member: staff_member, start_time: start_time, end_time: start_time + 1.hour)
      expect(booking).to be_valid
    end
  end
end
