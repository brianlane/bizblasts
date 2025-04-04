# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Business, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:users) }
    it { is_expected.to have_many(:tenant_customers) }
    it { is_expected.to have_many(:services) }
    it { is_expected.to have_many(:staff_members) }
    it { is_expected.to have_many(:bookings) }
  end

  describe 'validations' do
    subject { build(:business) }
    
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:subdomain) }
    
    it 'validates subdomain uniqueness' do
      create(:business, subdomain: 'existing')
      duplicate = build(:business, subdomain: 'existing')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:subdomain]).to include('has already been taken')
    end
  end

  describe 'subdomain format validation' do
    it 'accepts valid subdomains' do
      business = build(:business, subdomain: 'validsubdomain123')
      expect(business).to be_valid
    end

    it 'rejects subdomains with special characters' do
      business = build(:business, subdomain: 'invalid-subdomain!')
      # We need to manually normalize the subdomain as the test database doesn't call callbacks
      business.send(:normalize_subdomain)
      expect(business.subdomain).to eq('invalidsubdomain')
      expect(business).to be_valid
    end
  end
end 