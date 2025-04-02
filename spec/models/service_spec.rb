require 'rails_helper'

RSpec.describe Service, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:company) }
    it { is_expected.to have_many(:appointments).dependent(:restrict_with_error) }
  end

  describe 'validations' do
    let(:company) { create(:company) }
    subject { build(:service, company: company) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:company_id) }

    it { is_expected.to validate_presence_of(:price) }
    it { is_expected.to validate_numericality_of(:price).is_greater_than_or_equal_to(0) }

    it { is_expected.to validate_presence_of(:duration_minutes) }
    it { is_expected.to validate_numericality_of(:duration_minutes).only_integer.is_greater_than(0) }

    # Custom test for boolean validation without triggering warning
    it "validates that :active is a boolean" do
      # Test that nil is not valid
      service = build(:service, active: nil)
      expect(service.valid?).to be false
      expect(service.errors[:active]).to include("is not included in the list")
      
      # Test that false is valid
      service = build(:service, active: false)
      service.valid?
      expect(service.errors[:active]).to be_empty
      
      # Test that true is valid
      service = build(:service, active: true)
      service.valid?
      expect(service.errors[:active]).to be_empty
    end
  end
end
