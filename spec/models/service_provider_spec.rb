require 'rails_helper'

RSpec.describe ServiceProvider, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:company) }
    it { is_expected.to have_many(:appointments).dependent(:restrict_with_error) }
  end

  describe 'validations' do
    let(:company) { create(:company) }
    subject { build(:service_provider, company: company) }

    it { is_expected.to validate_presence_of(:company) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:company_id) }

    # Custom test for boolean validation without triggering warning
    it "validates that :active is a boolean" do
      # Test that nil is not valid
      provider = build(:service_provider, active: nil)
      expect(provider.valid?).to be false
      expect(provider.errors[:active]).to include("is not included in the list")
      
      # Test that false is valid
      provider = build(:service_provider, active: false)
      provider.valid?
      expect(provider.errors[:active]).to be_empty
      
      # Test that true is valid
      provider = build(:service_provider, active: true)
      provider.valid?
      expect(provider.errors[:active]).to be_empty
    end

    # Optional: Add tests for email/phone format if uncommented in model
  end
end 