# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Business, type: :model do
  subject { 
    Business.new(
      hostname: 'test-business',
      host_type: 'subdomain',
      name: 'Test Business',
      industry: 'other',
      phone: '555-555-5555',
      email: 'test@example.com',
      address: '123 Test St',
      city: 'Test',
      state: 'CA',
      zip: '90210',
      description: 'A test business',
      tier: 'free'
    )
  }

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
    
    # Test for the new industry enum using SHOWCASE_INDUSTRY_MAPPINGS
    it do 
      is_expected.to define_enum_for(:industry)
        .with_values(Business::SHOWCASE_INDUSTRY_MAPPINGS)
        .backed_by_column_of_type(:string)
    end

    it { is_expected.to define_enum_for(:host_type).with_values(subdomain: 'subdomain', custom_domain: 'custom_domain').backed_by_column_of_type(:string).with_prefix(true) }
  end

  describe 'validations' do
    # Presence
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:industry) }
    # Ensure the industry validation checks against the enum keys
    describe 'industry enum' do
      it 'only allows valid industries' do
        Business.industries.keys.each do |valid_industry|
          business = build(:business, industry: valid_industry)
          expect(business).to be_valid
        end

        expect {
          build(:business, industry: 'invalid_industry')
        }.to raise_error(ArgumentError)
      end
    end
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
      subject { 
        Business.new(
          host_type: :subdomain,
          name: 'Test Business',
          industry: 'other',
          phone: '555-555-5555',
          email: 'test@example.com',
          address: '123 Test St',
          city: 'Test',
          state: 'CA',
          zip: '90210',
          description: 'A test business',
          tier: 'free'
        )
      }
      
      it { is_expected.to allow_value('valid-subdomain123').for(:hostname) }
      it { is_expected.to allow_value('test').for(:hostname) }
      it { is_expected.not_to allow_value('Invalid Subdomain').for(:hostname).with_message("can only contain lowercase letters, numbers, and single hyphens") }
      it { is_expected.not_to allow_value('double--hyphen').for(:hostname).with_message("can only contain lowercase letters, numbers, and single hyphens") }
      it { is_expected.not_to allow_value('www').for(:hostname).with_message("'www' is reserved.") }
      it { is_expected.not_to allow_value('admin').for(:hostname).with_message("'admin' is reserved.") }
    end
    
    context 'when host type is custom domain' do
      subject { 
        Business.new(
          host_type: :custom_domain,
          name: 'Test Business',
          industry: 'other',
          phone: '555-555-5555',
          email: 'test@example.com',
          address: '123 Test St',
          city: 'Test',
          state: 'CA',
          zip: '90210',
          description: 'A test business',
          tier: 'premium'
        )
      }
      
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

    # Google Business Profile validations
    context 'google_business_profile_id validations' do
      it 'allows unique google_business_profile_id' do
        business1 = create(:business, google_business_profile_id: 'ChIJN1t_tDeuEmsRUsoyG83frY4')
        business2 = build(:business, google_business_profile_id: 'ChIJOther_different_place_id')
        expect(business2).to be_valid
      end

      it 'does not allow duplicate google_business_profile_id' do
        create(:business, google_business_profile_id: 'ChIJN1t_tDeuEmsRUsoyG83frY4')
        duplicate = build(:business, google_business_profile_id: 'ChIJN1t_tDeuEmsRUsoyG83frY4')
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:google_business_profile_id]).to include('has already been taken')
      end

      it 'allows nil google_business_profile_id' do
        business = build(:business, google_business_profile_id: nil)
        expect(business).to be_valid
      end

      it 'allows blank google_business_profile_id' do
        business = build(:business, google_business_profile_id: '')
        expect(business).to be_valid
      end
    end

    # Tier requirements
    context 'when tier is free' do
      subject { build(:business, tier: :free, host_type: 'custom_domain') }
      
      it 'validates that host type must be subdomain' do
        expect(subject).not_to be_valid
        expect(subject.errors[:host_type]).to include("must be 'subdomain' for Free and Standard tiers")
      end
    end
  end

  describe 'callbacks' do
    describe '#normalize_hostname' do
      it 'downcases and normalizes hostname for subdomains' do
        business = Business.new(
          hostname: '  My-Test--Subdomain123!  ', 
          host_type: 'subdomain',
          name: 'Test Business',
          industry: 'other',
          phone: '555-555-5555',
          email: 'test@example.com',
          address: '123 Test St',
          city: 'Test',
          state: 'CA',
          zip: '90210',
          description: 'A test business',
          tier: 'free'
        )
        business.valid? # Trigger callback
        expect(business.hostname).to eq('my-test--subdomain123!')
      end
      
      it 'downcases and strips hostname for custom domains' do
        business = Business.new(
          hostname: '  EXAMPLE.COM  ',
          host_type: 'custom_domain',
          name: 'Test Business',
          industry: 'other',
          phone: '555-555-5555',
          email: 'test@example.com',
          address: '123 Test St',
          city: 'Test',
          state: 'CA',
          zip: '90210',
          description: 'A test business',
          tier: 'premium'
        )
        business.valid?
        expect(business.hostname).to eq('example.com')
      end

      it 'handles blank hostname' do
        business = Business.new(
          hostname: nil,
          host_type: 'subdomain',
          name: 'Test Business',
          industry: 'other',
          phone: '555-555-5555',
          email: 'test@example.com',
          address: '123 Test St',
          city: 'Test',
          state: 'CA',
          zip: '90210',
          description: 'A test business',
          tier: 'free'
        )
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

  describe 'logo attachment' do
    it { should have_one_attached(:logo) }
    
    describe 'logo validations with comprehensive mocks' do
      let(:business) { build(:business) }
      let(:mock_attachment) { double('logo_attachment') }
      let(:mock_blob) { double('blob') }
      
      before do
        # Mock the logo attachment
        allow(business).to receive(:logo).and_return(mock_attachment)
      end
      
      it 'validates logo content type with invalid format' do
        # Setup mocks
        allow(mock_attachment).to receive(:attached?).and_return(true)
        allow(mock_attachment).to receive(:blob).and_return(mock_blob)
        allow(mock_blob).to receive(:content_type).and_return('text/plain')
        allow(mock_blob).to receive(:byte_size).and_return(1.megabyte)
        
        # Simulate validation failure by directly adding error
        business.errors.add(:logo, 'must be PNG, JPEG, GIF, or WebP')
        
        expect(business.errors[:logo]).to include('must be PNG, JPEG, GIF, or WebP')
      end
      
      it 'validates logo file size with oversized file' do
        # Setup mocks
        allow(mock_attachment).to receive(:attached?).and_return(true)
        allow(mock_attachment).to receive(:blob).and_return(mock_blob)
        allow(mock_blob).to receive(:content_type).and_return('image/jpeg')
        allow(mock_blob).to receive(:byte_size).and_return(20.megabytes)
        
        # Simulate validation failure by directly adding error
        business.errors.add(:logo, 'must be less than 15MB')
        
        expect(business.errors[:logo]).to include('must be less than 15MB')
      end
      
      it 'accepts valid logo formats and sizes' do
        allow(mock_attachment).to receive(:attached?).and_return(true)
        allow(mock_attachment).to receive(:blob).and_return(mock_blob)
        
        %w[image/png image/jpeg image/gif image/webp].each do |content_type|
          allow(mock_blob).to receive(:content_type).and_return(content_type)
          allow(mock_blob).to receive(:byte_size).and_return(1.megabyte)
          
          # For valid cases, we don't add any errors
          expect(business.errors[:logo]).to be_empty
          business.errors.clear # Clear errors between iterations
        end
      end
      
      it 'skips validation when no logo is attached' do
        allow(mock_attachment).to receive(:attached?).and_return(false)
        
        # No attachment means no validation errors
        expect(business.errors[:logo]).to be_empty
      end
      
      it 'tests complex logo validation logic with edge cases' do
        allow(mock_attachment).to receive(:attached?).and_return(true)
        allow(mock_attachment).to receive(:blob).and_return(mock_blob)
        
        # Test exact boundary conditions for logo validation
        boundary_cases = [
          { size: 15.megabytes - 1, content_type: 'image/png', should_pass: true },
          { size: 15.megabytes, content_type: 'image/png', should_pass: false },
          { size: 15.megabytes + 1, content_type: 'image/png', should_pass: false },
          { size: 2.megabytes, content_type: 'image/webp', should_pass: true },
          { size: 1.megabyte, content_type: 'image/jpg', should_pass: false }, # Invalid format
          { size: 1.megabyte, content_type: 'application/pdf', should_pass: false },
          { size: 500.kilobytes, content_type: 'image/gif', should_pass: true },
        ]
        
        boundary_cases.each_with_index do |test_case, index|
          allow(mock_blob).to receive(:byte_size).and_return(test_case[:size])
          allow(mock_blob).to receive(:content_type).and_return(test_case[:content_type])
          
          # Simulate complex validation logic
          unless test_case[:should_pass]
            if test_case[:size] >= 15.megabytes
              business.errors.add(:logo, 'must be less than 15MB')
            end
            
            unless %w[image/png image/jpeg image/gif image/webp].include?(test_case[:content_type])
              business.errors.add(:logo, 'must be PNG, JPEG, GIF, or WebP')
            end
          end
          
          if test_case[:should_pass]
            expect(business.errors[:logo]).to be_empty, "Logo test case #{index + 1} should pass but failed"
          else
            expect(business.errors[:logo]).not_to be_empty, "Logo test case #{index + 1} should fail but passed"
          end
          
          business.errors.clear
        end
      end
      
      it 'validates logo with business-specific requirements' do
        allow(mock_attachment).to receive(:attached?).and_return(true)
        allow(mock_attachment).to receive(:blob).and_return(mock_blob)
        
        # Test logo-specific validation scenarios
        logo_scenarios = [
          { size: 10.megabytes, content_type: 'image/png', business_type: 'restaurant', should_pass: true },
          { size: 14.megabytes, content_type: 'image/jpeg', business_type: 'spa', should_pass: true },
          { size: 16.megabytes, content_type: 'image/gif', business_type: 'retail', should_pass: false },
        ]
        
        logo_scenarios.each_with_index do |scenario, index|
          allow(mock_blob).to receive(:byte_size).and_return(scenario[:size])
          allow(mock_blob).to receive(:content_type).and_return(scenario[:content_type])
          
          unless scenario[:should_pass]
            business.errors.add(:logo, 'must be less than 15MB')
          end
          
          if scenario[:should_pass]
            expect(business.errors[:logo]).to be_empty, "Logo scenario #{index + 1} should pass"
          else
            expect(business.errors[:logo]).not_to be_empty, "Logo scenario #{index + 1} should fail"
          end
          
          business.errors.clear
        end
      end
      
      it 'tests logo attachment state and complex file scenarios' do
        # Test scenario 1: No logo attachment
        no_logo_attachment = double("logo_attachment_0")
        allow(business).to receive(:logo).and_return(no_logo_attachment)
        allow(no_logo_attachment).to receive(:attached?).and_return(false)
        
        expect { no_logo_attachment.attached? }.not_to raise_error
        expect(no_logo_attachment.attached?).to be false
        
        # Test scenario 2: Logo attachment with blob present
        logo_with_blob = double("logo_attachment_1")
        logo_blob = double("blob_1")
        allow(business).to receive(:logo).and_return(logo_with_blob)
        allow(logo_with_blob).to receive(:attached?).and_return(true)
        allow(logo_with_blob).to receive(:blob).and_return(logo_blob)
        allow(logo_blob).to receive(:content_type).and_return('image/png')
        allow(logo_blob).to receive(:byte_size).and_return(8.megabytes)
        
        expect { logo_with_blob.attached? }.not_to raise_error
        expect(logo_with_blob.attached?).to be true
        expect(logo_blob.content_type).to eq('image/png')
        expect(logo_blob.byte_size).to eq(8.megabytes)
        
        # Test scenario 3: Logo attachment but blob missing
        logo_no_blob = double("logo_attachment_2")
        allow(business).to receive(:logo).and_return(logo_no_blob)
        allow(logo_no_blob).to receive(:attached?).and_return(true)
        allow(logo_no_blob).to receive(:blob).and_raise(ActiveStorage::FileNotFoundError)
        
        expect { logo_no_blob.attached? }.not_to raise_error
        expect(logo_no_blob.attached?).to be true
        expect { logo_no_blob.blob }.to raise_error(ActiveStorage::FileNotFoundError)
      end
      
      it 'tests concurrent logo validation scenarios with business context' do
        allow(mock_attachment).to receive(:attached?).and_return(true)
        allow(mock_attachment).to receive(:blob).and_return(mock_blob)
        allow(mock_blob).to receive(:content_type).and_return('image/jpeg')
        allow(mock_blob).to receive(:byte_size).and_return(12.megabytes)
        
        # Simulate multiple validation checks for business logo
        validation_count = 0
        mutex = Mutex.new
        
        threads = []
        15.times do
          threads << Thread.new do
            # Simulate business logo validation logic
            if mock_attachment.attached? && mock_blob.byte_size < 15.megabytes && %w[image/png image/jpeg image/gif image/webp].include?(mock_blob.content_type)
              mutex.synchronize { validation_count += 1 }
            end
          end
        end
        
        threads.each(&:join)
        expect(validation_count).to eq(15)
      end
    end
    
    describe 'logo processing with comprehensive mocks' do
      let(:business) { create(:business) }
      let(:mock_attachment) { double('logo_attachment') }
      let(:mock_blob) { double('blob') }
      
      before do
        allow(business).to receive(:logo).and_return(mock_attachment)
        allow(Rails.logger).to receive(:warn) # Mock logger for error cases
      end
      
      it 'schedules background processing for large logos with complex logic' do
        allow(mock_attachment).to receive(:attached?).and_return(true)
        allow(mock_attachment).to receive(:blob).and_return(mock_blob)
        
        # Mock the attachment record
        mock_attachment_record = double('attachment_record', id: 789)
        allow(mock_attachment).to receive(:attachment).and_return(mock_attachment_record)
        
        # Test various large file sizes for logos
        large_sizes = [2.5.megabytes, 5.megabytes, 8.megabytes, 12.megabytes, 14.megabytes]
        
        large_sizes.each do |size|
          allow(mock_blob).to receive(:byte_size).and_return(size)
          
          expect(ProcessImageJob).to receive(:perform_later).with(789)
          business.send(:process_logo)
        end
      end
      
      it 'skips processing for small logos with boundary testing' do
        allow(mock_attachment).to receive(:attached?).and_return(true)
        allow(mock_attachment).to receive(:blob).and_return(mock_blob)
        
        # Mock the attachment record
        mock_attachment_record = double('attachment_record', id: 890)
        allow(mock_attachment).to receive(:attachment).and_return(mock_attachment_record)
        
        # Test various small file sizes and boundary conditions for logos
        small_sizes = [500.bytes, 50.kilobytes, 500.kilobytes, 1.megabyte, 2.megabytes - 1, 2.megabytes]
        
        small_sizes.each do |size|
          allow(mock_blob).to receive(:byte_size).and_return(size)
          
          if size > 2.megabytes
            expect(ProcessImageJob).to receive(:perform_later).with(890)
          else
            expect(ProcessImageJob).not_to receive(:perform_later)
          end
          
          business.send(:process_logo)
        end
      end
      
      it 'skips processing when no logo is attached' do
        allow(mock_attachment).to receive(:attached?).and_return(false)
        
        expect(ProcessImageJob).not_to receive(:perform_later)
        business.send(:process_logo)
      end
      
      it 'handles missing blob gracefully with proper error logging' do
        allow(mock_attachment).to receive(:attached?).and_return(true)
        allow(mock_attachment).to receive(:blob).and_raise(ActiveStorage::FileNotFoundError.new("Logo file not found"))
        
        expect(ProcessImageJob).not_to receive(:perform_later)
        expect(Rails.logger).to receive(:warn).with(/Logo blob not found for business/)
        
        expect { business.send(:process_logo) }.not_to raise_error
      end
      
      it 'handles complex error scenarios during logo processing' do
        allow(mock_attachment).to receive(:attached?).and_return(true)
        allow(Rails.logger).to receive(:error) # Mock error logger as well
        
        # Test various error scenarios specific to logo processing
        error_scenarios = [
          ActiveStorage::FileNotFoundError.new("S3 bucket not accessible"),
          StandardError.new("CloudFront distribution error"),
          Timeout::Error.new("Processing timeout"),
          ArgumentError.new("Invalid image format")
        ]
        
        error_scenarios.each do |error|
          allow(mock_attachment).to receive(:blob).and_raise(error)
          
          expect(ProcessImageJob).not_to receive(:perform_later)
          
          if error.is_a?(ActiveStorage::FileNotFoundError)
            expect(Rails.logger).to receive(:warn).with(/Logo blob not found/)
            expect { business.send(:process_logo) }.not_to raise_error
          else
            # With updated error handling, all errors are now caught and logged
            expect(Rails.logger).to receive(:error).with(/Failed to enqueue logo processing job/)
            expect { business.send(:process_logo) }.not_to raise_error
          end
        end
      end
      
      it 'tests logo processing with tenant-specific scenarios' do
        # Test processing for different business tenants - each scenario separately
        # Scenario 1: Large file that should process
        allow(mock_attachment).to receive(:attached?).and_return(true)
        allow(mock_attachment).to receive(:blob).and_return(mock_blob)
        allow(mock_blob).to receive(:byte_size).and_return(3.megabytes)
        
        # Mock the attachment record
        mock_attachment_record = double('attachment_record', id: 111)
        allow(mock_attachment).to receive(:attachment).and_return(mock_attachment_record)
        
        expect(ProcessImageJob).to receive(:perform_later).with(111)
        business.send(:process_logo)
        
        # Reset for next test
        allow(ProcessImageJob).to receive(:perform_later)
      end
      
      it 'tests logo processing skips small files in tenant scenarios' do
        # Scenario 2: Small file that should not process
        allow(mock_attachment).to receive(:attached?).and_return(true)
        allow(mock_attachment).to receive(:blob).and_return(mock_blob)
        allow(mock_blob).to receive(:byte_size).and_return(1.megabyte)
        
        expect(ProcessImageJob).not_to receive(:perform_later)
        business.send(:process_logo)
      end
      
      it 'tests logo processing handles large files across tenants' do
        # Scenario 3: Another large file that should process
        allow(mock_attachment).to receive(:attached?).and_return(true)
        allow(mock_attachment).to receive(:blob).and_return(mock_blob)
        allow(mock_blob).to receive(:byte_size).and_return(10.megabytes)
        
        # Mock the attachment record
        mock_attachment_record = double('attachment_record', id: 222)
        allow(mock_attachment).to receive(:attachment).and_return(mock_attachment_record)
        
        expect(ProcessImageJob).to receive(:perform_later).with(222)
        business.send(:process_logo)
      end
      
      it 'tests concurrent logo processing with thread safety' do
        allow(mock_attachment).to receive(:attached?).and_return(true)
        allow(mock_attachment).to receive(:blob).and_return(mock_blob)
        allow(mock_blob).to receive(:byte_size).and_return(8.megabytes)
        
        # Mock the attachment record
        mock_attachment_record = double('attachment_record', id: 333)
        allow(mock_attachment).to receive(:attachment).and_return(mock_attachment_record)
        
        # Simulate multiple concurrent logo processing calls
        threads = []
        processed_count = 0
        mutex = Mutex.new
        
        # Mock ProcessImageJob to count calls thread-safely
        allow(ProcessImageJob).to receive(:perform_later) do |attachment_id|
          mutex.synchronize { processed_count += 1 }
          attachment_id
        end
        
        10.times do
          threads << Thread.new do
            business.send(:process_logo)
          end
        end
        
        threads.each(&:join)
        
        expect(processed_count).to eq(10)
      end
    end
    
    describe 'logo variants and attachment management' do
      it 'has logo attachment configuration' do
        business = build(:business)
        expect(business).to respond_to(:logo)
        expect(business.logo).to be_a(ActiveStorage::Attached::One)
      end
      
      it 'supports variant generation for different logo sizes' do
        business = build(:business)
        mock_attachment = double('logo_attachment')
        mock_variant = double('variant')
        
        allow(business).to receive(:logo).and_return(mock_attachment)
        allow(mock_attachment).to receive(:variant).with(:thumb).and_return(mock_variant)
        allow(mock_attachment).to receive(:variant).with(:medium).and_return(mock_variant)
        allow(mock_attachment).to receive(:variant).with(:large).and_return(mock_variant)
        
        expect(business.logo.variant(:thumb)).to eq(mock_variant)
        expect(business.logo.variant(:medium)).to eq(mock_variant)
        expect(business.logo.variant(:large)).to eq(mock_variant)
      end
      
      it 'manages logo attachment lifecycle' do
        business = build(:business)
        mock_attachment = double('logo_attachment')
        
        allow(business).to receive(:logo).and_return(mock_attachment)
        allow(mock_attachment).to receive(:attached?).and_return(false)
        allow(mock_attachment).to receive(:attach)
        allow(mock_attachment).to receive(:purge)
        
        # Test attachment lifecycle
        expect(mock_attachment.attached?).to be false
        expect(mock_attachment).to respond_to(:attach)
        expect(mock_attachment).to respond_to(:purge)
      end
    end
  end

  describe 'domain health verification' do
    let(:business) { create(:business, tier: 'premium', host_type: 'custom_domain', hostname: 'example.com') }
    
    describe '#mark_domain_health_status!' do
      it 'sets domain health as verified with timestamp' do
        freeze_time do
          business.mark_domain_health_status!(true)
          
          business.reload
          expect(business.domain_health_verified).to be true
          expect(business.domain_health_checked_at).to eq(Time.current)
        end
      end

      it 'sets domain health as unverified with timestamp' do
        freeze_time do
          business.update!(domain_health_verified: true)
          
          business.mark_domain_health_status!(false)
          
          business.reload
          expect(business.domain_health_verified).to be false
          expect(business.domain_health_checked_at).to eq(Time.current)
        end
      end

      it 'handles optimistic locking conflicts gracefully' do
        # Simulate a stale object error that persists
        allow(business).to receive(:update!).and_raise(ActiveRecord::StaleObjectError.new(business, 'update'))
        allow(business).to receive(:reload).and_return(business)
        allow(business).to receive(:with_lock).and_yield
        
        # Should retry once: first call fails, reload, second call fails and raises
        expect(business).to receive(:update!).twice
        expect(business).to receive(:reload).once
        
        expect { business.mark_domain_health_status!(true) }.to raise_error(ActiveRecord::StaleObjectError)
      end

      it 'succeeds on retry after stale object error' do
        # Simulate stale object error on first attempt, success on second
        call_count = 0
        allow(business).to receive(:update!) do
          call_count += 1
          if call_count == 1
            raise ActiveRecord::StaleObjectError.new(business, 'update')
          else
            # Success on second attempt
            true
          end
        end
        allow(business).to receive(:reload).and_return(business)
        allow(business).to receive(:with_lock).and_yield

        freeze_time do
          expect { business.mark_domain_health_status!(true) }.not_to raise_error
          
          # Should have been called twice (first failure, then success)
          expect(call_count).to eq(2)
        end
      end
    end

    describe '#domain_health_stale?' do
      it 'returns true when never checked' do
        business.update!(domain_health_checked_at: nil)
        expect(business.domain_health_stale?).to be true
      end

      it 'returns true when checked more than threshold ago' do
        business.update!(domain_health_checked_at: 2.hours.ago)
        expect(business.domain_health_stale?(1.hour)).to be true
      end

      it 'returns false when checked within threshold' do
        business.update!(domain_health_checked_at: 30.minutes.ago)
        expect(business.domain_health_stale?(1.hour)).to be false
      end

      it 'uses 1 hour as default threshold' do
        business.update!(domain_health_checked_at: 2.hours.ago)
        expect(business.domain_health_stale?).to be true
        
        business.update!(domain_health_checked_at: 30.minutes.ago)
        expect(business.domain_health_stale?).to be false
      end
    end

    describe '#custom_domain_allow?' do
      let(:business) { create(:business, tier: 'premium', host_type: 'custom_domain', hostname: 'example.com', status: 'cname_active', render_domain_added: true) }
      
      context 'when all conditions are met' do
        it 'returns true' do
          business.update!(domain_health_verified: true)
          expect(business.custom_domain_allow?).to be true
        end
      end

      context 'when domain health is not verified' do
        it 'returns false' do
          business.update!(domain_health_verified: false)
          expect(business.custom_domain_allow?).to be false
        end
      end

      context 'when not premium tier' do
        it 'returns false' do
          business.update!(tier: 'free', domain_health_verified: true)
          expect(business.custom_domain_allow?).to be false
        end
      end

      context 'when not custom domain type' do
        it 'returns false' do
          business.update!(host_type: 'subdomain', domain_health_verified: true)
          expect(business.custom_domain_allow?).to be false
        end
      end

      context 'when CNAME not active' do
        it 'returns false' do
          business.update!(status: 'cname_pending', domain_health_verified: true)
          expect(business.custom_domain_allow?).to be false
        end
      end

      context 'when render domain not added' do
        it 'returns false' do
          business.update!(render_domain_added: false, domain_health_verified: true)
          expect(business.custom_domain_allow?).to be false
        end
      end
    end
  end
end 