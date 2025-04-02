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

    it { is_expected.to validate_inclusion_of(:active).in_array([true, false]) }
  end
end
