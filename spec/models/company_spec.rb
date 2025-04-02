# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Company, type: :model do
  describe 'validations' do
    subject { build(:company) }
    
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:subdomain) }
    
    # We can't use shoulda matchers here because of the normalization
    it 'validates subdomain uniqueness' do
      create(:company, subdomain: 'existing')
      duplicate = build(:company, subdomain: 'existing')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:subdomain]).to include('has already been taken')
    end
    
    it 'validates subdomain uniqueness case-insensitively' do
      create(:company, subdomain: 'lowercasetest')
      duplicate = build(:company, subdomain: 'LOWERCASETEST')
      
      # Due to the normalize_subdomain callback, this will be invalid
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:subdomain]).to include('has already been taken')
    end
  end

  describe 'subdomain format validation' do
    it 'accepts valid subdomains' do
      company = build(:company, subdomain: 'validsubdomain123')
      expect(company).to be_valid
    end

    it 'rejects subdomains with special characters before normalization' do
      # The normalize_subdomain callback will clean this up,
      # so we need to skip it to test the validation
      company = build(:company)
      
      # Set an invalid subdomain directly before validation
      allow(company).to receive(:normalize_subdomain) { nil } # Disable callback
      company.subdomain = 'invalid-subdomain!'
      
      expect(company).not_to be_valid
      # Use the actual error message rather than the translation key
      expect(company.errors[:subdomain]).to include("only allows lowercase letters and numbers without spaces")
    end
    
    it 'normalizes invalid subdomains and makes them valid' do
      company = build(:company, subdomain: 'invalid-subdomain!')
      expect(company).to be_valid
      expect(company.subdomain).to eq('invalidsubdomain')
    end
  end

  describe 'callbacks' do
    it 'normalizes the subdomain before validation' do
      company = create(:company, subdomain: 'MIXEDCASE123')
      expect(company.subdomain).to eq('mixedcase123')
    end
    
    it 'removes non-alphanumeric characters from subdomain' do
      company = create(:company, subdomain: 'test-subdomain!')
      expect(company.subdomain).to eq('testsubdomain')
    end
  end

  describe '.current' do
    it 'returns the current tenant' do
      company = create(:company)
      ActsAsTenant.current_tenant = company
      expect(Company.current).to eq(company)
      ActsAsTenant.current_tenant = nil
    end
  end
end 