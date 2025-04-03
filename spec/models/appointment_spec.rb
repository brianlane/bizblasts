require 'rails_helper'

RSpec.describe Appointment, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:company) }
    it { is_expected.to belong_to(:service) }
    it { is_expected.to belong_to(:service_provider) }
    it { is_expected.to belong_to(:customer) }
  end

  describe 'validations' do
    # Ensure the base subject is valid by default
    let(:company) { create(:company) }
    let(:service_provider) { create(:service_provider, :with_standard_availability, company: company) }
    let(:customer) { create(:customer, company: company) }
    let(:service) { create(:service, company: company) }
    let(:valid_start_time) { Time.zone.parse('2024-10-21 10:00:00') } # Time when provider is available

    subject do
      build(:appointment, 
            company: company, 
            service_provider: service_provider, 
            customer: customer, 
            service: service,
            start_time: valid_start_time, 
            end_time: valid_start_time + service.duration_minutes.minutes)
    end

    it { is_expected.to validate_presence_of(:company) }
    it { is_expected.to validate_presence_of(:service) }
    it { is_expected.to validate_presence_of(:service_provider) }
    it { is_expected.to validate_presence_of(:customer) }
    it { is_expected.to validate_presence_of(:start_time) }
    it { is_expected.to validate_presence_of(:end_time) }

    # Custom validation test
    it 'is invalid if end_time is before start_time' do
      appointment = build(:appointment, start_time: Time.current, end_time: Time.current - 1.hour)
      expect(appointment).not_to be_valid
      expect(appointment.errors[:end_time]).to include("must be after the start time")
    end

    it 'is valid if end_time is after start_time' do
      # Ensure the provider is available at the chosen start time for this specific test
      start_time = Time.zone.parse('2024-10-21 10:00:00') # A time provider is known to be available
      appointment = build(:appointment, service_provider: service_provider, start_time: start_time, end_time: start_time + 1.hour)
      expect(appointment).to be_valid
    end

    # Context block for numericality check
    context "when checking price numericality" do
      # Remove the standard matcher as it conflicts with type casting
      # it { is_expected.to validate_numericality_of(:price).is_greater_than_or_equal_to(0).allow_nil }

      it "is invalid with a non-numeric price" do
        subject.price = "not-a-number"
        expect(subject).not_to be_valid
        expect(subject.errors[:price]).to include("is not a number")
      end

      it "is valid with a valid price" do
        subject.price = 100.00
        expect(subject).to be_valid
      end

      it "is valid with a nil price" do
        subject.price = nil
        expect(subject).to be_valid
      end
      
      it "is valid with zero price" do
        subject.price = 0
        expect(subject).to be_valid
      end
      
      it "is invalid with a negative price" do
         subject.price = -10
         expect(subject).not_to be_valid
         expect(subject.errors[:price]).to include("must be greater than or equal to 0")
      end
    end
  end
end 