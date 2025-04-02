require 'rails_helper'

RSpec.describe Customer, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:company) }
    it { is_expected.to have_many(:appointments).dependent(:destroy) }
  end

  describe 'validations' do
    # Need to create a company first because of the uniqueness scope
    let(:company) { create(:company) }
    subject { build(:customer, company: company) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to allow_value('user@example.com').for(:email) }
    it { is_expected.not_to allow_value('userexample.com').for(:email) }

    # Test uniqueness scoped to company_id
    it 'validates uniqueness of email scoped to company_id' do
      create(:customer, email: 'unique@example.com', company: company)
      # Use subject for the second record
      expect(subject).to validate_uniqueness_of(:email).scoped_to(:company_id).case_insensitive
    end

    it 'allows duplicate emails across different companies' do
      company1 = create(:company)
      company2 = create(:company)
      create(:customer, email: 'duplicate@example.com', company: company1)
      customer2 = build(:customer, email: 'duplicate@example.com', company: company2)
      expect(customer2).to be_valid
    end
  end
end
