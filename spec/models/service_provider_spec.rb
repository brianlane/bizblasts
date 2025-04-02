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
    it { is_expected.to validate_inclusion_of(:active).in_array([true, false]) }

    # Optional: Add tests for email/phone format if uncommented in model
  end
end 