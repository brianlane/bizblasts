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

    # Add tests for optional email/phone format validation if needed
    it { is_expected.to allow_value("test@example.com").for(:email) }
    it { is_expected.to allow_value(nil).for(:email) }
    it { is_expected.not_to allow_value("invalid-email").for(:email) }
    
    it { is_expected.to allow_value("123-456-7890").for(:phone) }
    it { is_expected.to allow_value(nil).for(:phone) }
    it { is_expected.to allow_value("+1 (555) 123-4567").for(:phone) }
    # Add more specific phone format tests if the regex is strict
    
    # Tests for availability JSON structure (basic)
    context 'with availability validation' do
      let(:valid_availability) do 
        {
          monday: [{ start: '09:00', end: '17:00' }],
          tuesday: [], # Closed
          exceptions: {
            '2024-12-25': [] # Holiday
          }
        }
      end

      it 'is valid with correct availability structure' do
        provider = build(:service_provider, availability: valid_availability)
        expect(provider).to be_valid
      end

      it 'is invalid with incorrect top-level key' do
        invalid_data = valid_availability.merge(mondaay: [])
        provider = build(:service_provider, availability: invalid_data)
        expect(provider).not_to be_valid
        expect(provider.errors[:availability]).to include(/contains invalid key: 'mondaay'/)
      end

      it 'is invalid with incorrect interval format' do
        invalid_data = { monday: 'not_an_array' } # This is not an array
        provider = build(:service_provider, availability: invalid_data)
        expect(provider).not_to be_valid
        expect(provider.errors[:availability]).to include("value for 'monday' must be an array of time intervals")
      end
      
      it 'is invalid with incorrect time format' do
        invalid_data = { monday: [{ start: '9:00am', end: '17:00' }] }
        provider = build(:service_provider, availability: invalid_data)
        expect(provider).not_to be_valid
        expect(provider.errors[:availability]).to include("invalid start time for interval #1 for 'monday': '9:00am'. Use HH:MM format.")
      end
      
      it 'is invalid with incorrect exception date format' do
        invalid_data = { exceptions: { '25-12-2024': [] } }
        provider = build(:service_provider, availability: invalid_data)
        expect(provider).not_to be_valid
        expect(provider.errors[:availability]).to include("contains invalid date format in exceptions: '25-12-2024'. Use YYYY-MM-DD.")
      end
      
      it 'is invalid with start time after end time' do
        invalid_data = { monday: [{ start: '14:00', end: '12:00' }] }
        provider = build(:service_provider, availability: invalid_data)
        expect(provider).not_to be_valid
        expect(provider.errors[:availability]).to include(/start time must be before end time/)
      end
    end
  end

  # New tests for available_at?
  describe '#available_at?' do
    # Create a provider that will pass validation
    let(:provider) do
      # Use build_stubbed to avoid hitting the database and validation issues
      build_stubbed(:service_provider, :with_standard_availability, active: true)
    end

    context 'when provider is inactive' do
      before { provider.active = false }
      it 'returns false' do
        monday_morning = Time.zone.parse('2024-10-21 09:30:00') # A random Monday
        expect(provider.available_at?(monday_morning)).to be false
      end
    end

    context 'based on weekly schedule' do
      it 'returns true during working hours on Monday morning' do
        monday_morning = Time.zone.parse('2024-10-21 09:30:00') # A random Monday
        expect(provider.available_at?(monday_morning)).to be true
      end
      
      it 'returns true during working hours on Monday afternoon' do
        monday_afternoon = Time.zone.parse('2024-10-21 14:00:00') # A random Monday
        expect(provider.available_at?(monday_afternoon)).to be true
      end
      
      it 'returns false during lunch break on Monday' do
        monday_lunch = Time.zone.parse('2024-10-21 12:30:00') # A random Monday
        expect(provider.available_at?(monday_lunch)).to be false
      end
      
      it 'returns false before start time on Monday' do
        monday_early = Time.zone.parse('2024-10-21 08:59:00') # A random Monday
        expect(provider.available_at?(monday_early)).to be false
      end
      
      it 'returns false exactly at end time on Monday' do
        monday_end = Time.zone.parse('2024-10-21 17:00:00') # A random Monday
        expect(provider.available_at?(monday_end)).to be false # Available up to, but not including, end time
      end
      
      it 'returns true during working hours on Tuesday' do
        tuesday = Time.zone.parse('2024-10-22 11:00:00') # A random Tuesday
        expect(provider.available_at?(tuesday)).to be true
      end

      it 'returns false on Wednesday (closed day)' do
        wednesday = Time.zone.parse('2024-10-23 11:00:00') # A random Wednesday
        expect(provider.available_at?(wednesday)).to be false
      end
    end
    
    context 'based on exceptions' do
      it 'returns false on a holiday exception date' do
        christmas = Time.zone.parse('2024-12-25 11:00:00') # Should be Tuesday based on schedule, but is exception
        expect(provider.available_at?(christmas)).to be false
      end
      
      it 'returns true during special hours on an exception date' do
        thanksgiving_morning = Time.zone.parse('2024-11-28 11:00:00') # A Thursday
        expect(provider.available_at?(thanksgiving_morning)).to be true
      end
      
      it 'returns false outside special hours on an exception date' do
        thanksgiving_afternoon = Time.zone.parse('2024-11-28 14:30:00') # A Thursday
        expect(provider.available_at?(thanksgiving_afternoon)).to be false
      end
    end
    
    context 'with missing or invalid data' do
       it 'returns false if time format is invalid' do
         provider_invalid = build_stubbed(:service_provider, 
           active: true,
           availability: { "monday" => [{ "start" => "invalid", "end" => "17:00" }] }
         )
         monday = Time.zone.parse('2024-10-21 14:00:00')
         # The validate_availability_structure should fail this normally,
         # but we're testing the available_at? method's ability to handle invalid data
         expect(provider_invalid.available_at?(monday)).to be false
       end
       
       it 'handles missing day key gracefully returning false' do
         friday = Time.zone.parse('2024-10-25 10:00:00') # Friday not defined in availability
         provider_without_friday = build_stubbed(:service_provider,
           active: true,
           availability: { "monday" => [{ "start" => "09:00", "end" => "17:00" }] }
         )
         expect(provider_without_friday.available_at?(friday)).to be false
       end
       
       it 'handles nil availability gracefully returning false' do
         provider_nil = build_stubbed(:service_provider, active: true, availability: nil)
         monday = Time.zone.parse('2024-10-21 10:00:00') 
         expect(provider_nil.available_at?(monday)).to be false
       end
    end
  end
end 