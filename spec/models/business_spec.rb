# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Business, type: :model do
  subject { build(:business) } # Use subject for concise tests

  describe 'associations' do
    it { is_expected.to belong_to(:service_template).optional }
    it { is_expected.to have_many(:users) }
    it { is_expected.to have_many(:tenant_customers) }
    it { is_expected.to have_many(:services) }
    it { is_expected.to have_many(:staff_members) }
    it { is_expected.to have_many(:bookings) }
    it { is_expected.to have_many(:invoices) }
    it { is_expected.to have_many(:marketing_campaigns) }
    it { is_expected.to have_many(:promotions) }
    it { is_expected.to have_many(:pages) }
    it { is_expected.to have_many(:client_businesses) }
    it { is_expected.to have_many(:clients).through(:client_businesses).source(:user) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:tier).with_values(free: 'free', standard: 'standard', premium: 'premium').backed_by_column_of_type(:string).with_suffix(true) }
    it { is_expected.to define_enum_for(:industry).with_values(hair_salon: 'hair_salon', beauty_spa: 'beauty_spa', massage_therapy: 'massage_therapy', fitness_studio: 'fitness_studio', tutoring_service: 'tutoring_service', cleaning_service: 'cleaning_service', handyman_service: 'handyman_service', pet_grooming: 'pet_grooming', photography: 'photography', consulting: 'consulting', other: 'other').backed_by_column_of_type(:string) }
    it { is_expected.to define_enum_for(:host_type).with_values(subdomain: 'subdomain', custom_domain: 'custom_domain').backed_by_column_of_type(:string).with_prefix(true) }
  end

  describe 'validations' do
    # Presence
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:industry) }
    it { is_expected.to validate_presence_of(:phone) }
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_presence_of(:address) }
    it { is_expected.to validate_presence_of(:city) }
    it { is_expected.to validate_presence_of(:state) }
    it { is_expected.to validate_presence_of(:zip) }
    it { is_expected.to validate_presence_of(:description) }
    it { is_expected.to validate_presence_of(:tier) }
    it { is_expected.to validate_presence_of(:hostname) }
    it { is_expected.to validate_presence_of(:host_type) }

    # Hostname Format
    context 'when host type is subdomain' do
      subject { build(:business, host_type: :subdomain) }
      
      it { is_expected.to allow_value('valid-subdomain123').for(:hostname) }
      it { is_expected.to allow_value('test').for(:hostname) }
      it { is_expected.not_to allow_value('Invalid Subdomain').for(:hostname).with_message("can only contain lowercase letters, numbers, and single hyphens") }
      it { is_expected.not_to allow_value('double--hyphen').for(:hostname).with_message("can only contain lowercase letters, numbers, and single hyphens") }
      it { is_expected.not_to allow_value('www').for(:hostname).with_message("'www' is reserved.") }
      it { is_expected.not_to allow_value('admin').for(:hostname).with_message("'admin' is reserved.") }
    end
    
    context 'when host type is custom domain' do
      subject { build(:business, host_type: :custom_domain) }
      
      it { is_expected.to allow_value('example.com').for(:hostname) }
      it { is_expected.to allow_value('sub.example-test.co.uk').for(:hostname) }  
      it { is_expected.not_to allow_value('invalid domain').for(:hostname).with_message("is not a valid domain name") }
      it { is_expected.not_to allow_value('example..com').for(:hostname).with_message("is not a valid domain name") }
      it { is_expected.not_to allow_value('-example.com').for(:hostname).with_message("is not a valid domain name") }
    end

    # Uniqueness
    context 'uniqueness checks' do
      let!(:existing_business) { create(:business, hostname: 'taken', host_type: 'subdomain') }
      let!(:existing_custom_domain) { create(:business, hostname: 'taken.com', host_type: 'custom_domain') }

      it 'validates hostname uniqueness' do
        duplicate_hostname = build(:business, hostname: 'taken')
        expect(duplicate_hostname).not_to be_valid
        expect(duplicate_hostname.errors[:hostname]).to include('has already been taken')
      end

      it 'allows updating without changing unique hostname' do
        existing_business.name = "New Name"
        expect(existing_business).to be_valid
      end
    end
    
    # Tier requirements
    context 'when tier is free' do
      subject { build(:business, tier: :free, host_type: 'custom_domain') }
      
      it 'validates that host type must be subdomain' do
        expect(subject).not_to be_valid
        expect(subject.errors[:host_type]).to include("must be 'subdomain' for the Free tier")
      end
    end
  end

  describe 'callbacks' do
    describe '#normalize_hostname' do
      it 'downcases and normalizes hostname for subdomains' do
        business = build(:business, hostname: '  My-Test--Subdomain123!  ', host_type: 'subdomain')
        business.valid? # Trigger callback
        expect(business.hostname).to eq('my-test--subdomain123!')
      end
      
      it 'downcases and strips hostname for custom domains' do
        business = build(:business, hostname: '  EXAMPLE.COM  ', host_type: 'custom_domain')  
        business.valid?
        expect(business.hostname).to eq('example.com')
      end

      it 'handles blank hostname' do
        business = build(:business, hostname: nil)
        expect(business).not_to be_valid
        expect(business.errors[:hostname]).to include("can't be blank")
      end
    end
  end

  describe 'domain coverage methods' do
    let(:premium_business) { build(:business, tier: 'premium', host_type: 'custom_domain') }
    let(:free_business) { build(:business, tier: 'free', host_type: 'subdomain') }
    let(:standard_subdomain) { build(:business, tier: 'standard', host_type: 'subdomain') }
    let(:standard_custom) { build(:business, tier: 'standard', host_type: 'custom_domain') }

    describe '#eligible_for_domain_coverage?' do
      it 'returns true for premium tier with custom domain' do
        expect(premium_business.eligible_for_domain_coverage?).to be true
      end

      it 'returns false for free tier regardless of host type' do
        expect(free_business.eligible_for_domain_coverage?).to be false
      end

      it 'returns false for standard tier with subdomain' do
        expect(standard_subdomain.eligible_for_domain_coverage?).to be false
      end

      it 'returns false for standard tier with custom domain' do
        expect(standard_custom.eligible_for_domain_coverage?).to be false
      end
    end

    describe '#domain_coverage_limit' do
      it 'returns 20.0 for all businesses' do
        expect(premium_business.domain_coverage_limit).to eq(20.0)
        expect(free_business.domain_coverage_limit).to eq(20.0)
      end
    end

    describe '#domain_coverage_available?' do
      it 'returns true for eligible business without coverage applied' do
        expect(premium_business.domain_coverage_available?).to be true
      end

      it 'returns false for eligible business with coverage already applied' do
        premium_business.domain_coverage_applied = true
        expect(premium_business.domain_coverage_available?).to be false
      end

      it 'returns false for non-eligible business' do
        expect(free_business.domain_coverage_available?).to be false
      end
    end

    describe '#apply_domain_coverage!' do
      let(:premium_business_saved) { create(:business, tier: 'premium', host_type: 'custom_domain') }

      it 'applies coverage for eligible business with valid cost' do
        result = premium_business_saved.apply_domain_coverage!(15.99, 'Test domain registration')
        
        expect(result).to be true
        premium_business_saved.reload
        expect(premium_business_saved.domain_coverage_applied?).to be true
        expect(premium_business_saved.domain_cost_covered).to eq(15.99)
        expect(premium_business_saved.domain_coverage_notes).to eq('Test domain registration')
        expect(premium_business_saved.domain_renewal_date).to be_within(1.day).of(1.year.from_now.to_date)
      end

      it 'fails for cost exceeding limit' do
        result = premium_business_saved.apply_domain_coverage!(25.00)
        
        expect(result).to be false
        premium_business_saved.reload
        expect(premium_business_saved.domain_coverage_applied?).to be false
      end

      it 'fails for non-eligible business' do
        free_business_saved = create(:business, tier: 'free', host_type: 'subdomain')
        result = free_business_saved.apply_domain_coverage!(10.00)
        
        expect(result).to be false
        free_business_saved.reload
        expect(free_business_saved.domain_coverage_applied?).to be false
      end
    end

    describe '#domain_coverage_status' do
      it 'returns :not_eligible for non-eligible business' do
        expect(free_business.domain_coverage_status).to eq(:not_eligible)
      end

      it 'returns :available for eligible business without coverage' do
        expect(premium_business.domain_coverage_status).to eq(:available)
      end

      it 'returns :applied for eligible business with coverage' do
        premium_business.domain_coverage_applied = true
        expect(premium_business.domain_coverage_status).to eq(:applied)
      end
    end
  end
end 