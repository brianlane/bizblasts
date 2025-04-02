require 'rails_helper'

RSpec.describe Appointment, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:company) }
    it { is_expected.to belong_to(:service) }
    it { is_expected.to belong_to(:service_provider) }
    it { is_expected.to belong_to(:customer) }
  end

  describe 'validations' do
    subject { build(:appointment) }

    it { is_expected.to validate_presence_of(:company) }
    it { is_expected.to validate_presence_of(:service) }
    it { is_expected.to validate_presence_of(:service_provider) }
    it { is_expected.to validate_presence_of(:customer) }
    it { is_expected.to validate_presence_of(:client_name) } # From migration
    it { is_expected.to validate_presence_of(:start_time) }
    it { is_expected.to validate_presence_of(:end_time) }

    # Custom validation test
    it 'is invalid if end_time is before start_time' do
      appointment = build(:appointment, start_time: Time.current, end_time: Time.current - 1.hour)
      expect(appointment).not_to be_valid
      expect(appointment.errors[:end_time]).to include("must be after the start time")
    end

    it 'is valid if end_time is after start_time' do
      appointment = build(:appointment, start_time: Time.current, end_time: Time.current + 1.hour)
      expect(appointment).to be_valid
    end
  end
end 